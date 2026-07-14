#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>

#include "esp_check.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "ads129x.h"
#include "board_init.h"
#include "command_router.h"
#include "connectivity_manager.h"
#include "display_manager.h"
#include "ecg_pipeline.h"
#include "ecg_task.h"
#include "health.h"
#include "led_manager.h"
#include "local_api.h"
#include "logging_manager.h"
#include "ota_manager.h"
#include "power_manager.h"
#include "provisioning.h"
#include "remote_service.h"
#include "sd_session.h"
#include "sensor_manager.h"
#include "storage_writer.h"
#include "telemetry.h"
#include "usb_logging.h"

/* app_main owns lifecycle and supervision. The individual components own the
 * hardware protocol, signal handling and record construction. This separation
 * makes acquisition timing independent of logging, display and connectivity. */

static const char *TAG = "motemasens_app";

enum {
    APP_EVT_NVS_READY       = BIT0,
    APP_EVT_BOARD_READY     = BIT1,
    APP_EVT_STORAGE_READY   = BIT2,
    APP_EVT_ECG_READY       = BIT3,
    APP_EVT_ACQUIRING       = BIT4,
    APP_EVT_FAULT           = BIT5,
};

typedef enum {
    APP_BOOT_RESET = 0,
    APP_BOOT_NVS,
    APP_BOOT_EVENT_LOOP,
    APP_BOOT_BOARD,
    APP_BOOT_SERVICES,
    APP_BOOT_ACQUISITION,
    APP_BOOT_RUNNING,
    APP_BOOT_FAILED,
} app_boot_state_t;

typedef struct {
    EventGroupHandle_t events;
    TaskHandle_t supervisor_task;
    app_boot_state_t boot_state;
    esp_err_t first_error;
    uint32_t boot_time_us;
    uint32_t last_valid_samples;
    uint32_t consecutive_fault_windows;
} app_context_t;

static app_context_t s_app;

static const char *boot_state_name(app_boot_state_t state)
{
    switch (state) {
    case APP_BOOT_RESET: return "reset";
    case APP_BOOT_NVS: return "nvs";
    case APP_BOOT_EVENT_LOOP: return "event_loop";
    case APP_BOOT_BOARD: return "board";
    case APP_BOOT_SERVICES: return "services";
    case APP_BOOT_ACQUISITION: return "acquisition";
    case APP_BOOT_RUNNING: return "running";
    case APP_BOOT_FAILED: return "failed";
    default: return "unknown";
    }
}

static void record_boot_error(esp_err_t error, const char *operation)
{
    if (s_app.first_error == ESP_OK) {
        s_app.first_error = error;
    }
    s_app.boot_state = APP_BOOT_FAILED;
    xEventGroupSetBits(s_app.events, APP_EVT_FAULT);
    ESP_LOGE(TAG, "boot operation failed: %s (%s)", operation, esp_err_to_name(error));
}

static esp_err_t initialise_nvs(void)
{
    s_app.boot_state = APP_BOOT_NVS;
    esp_err_t result = nvs_flash_init();
    if (result == ESP_ERR_NVS_NO_FREE_PAGES || result == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_RETURN_ON_ERROR(nvs_flash_erase(), TAG, "nvs erase");
        result = nvs_flash_init();
    }
    if (result == ESP_OK) {
        xEventGroupSetBits(s_app.events, APP_EVT_NVS_READY);
    }
    return result;
}

static esp_err_t initialise_platform(void)
{
    s_app.boot_state = APP_BOOT_EVENT_LOOP;
    ESP_RETURN_ON_ERROR(esp_event_loop_create_default(), TAG, "event loop");

    s_app.boot_state = APP_BOOT_BOARD;
    ESP_RETURN_ON_ERROR(board_init(), TAG, "board init");
    xEventGroupSetBits(s_app.events, APP_EVT_BOARD_READY);
    return ESP_OK;
}

static esp_err_t initialise_services(void)
{
    s_app.boot_state = APP_BOOT_SERVICES;
    ESP_RETURN_ON_ERROR(health_init(), TAG, "health init");
    ESP_RETURN_ON_ERROR(power_manager_init(), TAG, "power init");
    ESP_RETURN_ON_ERROR(led_manager_init(), TAG, "led init");
    ESP_RETURN_ON_ERROR(storage_writer_init(), TAG, "storage init");
    ESP_RETURN_ON_ERROR(sd_session_init(), TAG, "sd session init");
    ESP_RETURN_ON_ERROR(usb_logging_init(), TAG, "usb logging init");
    ESP_RETURN_ON_ERROR(logging_manager_init(), TAG, "logging init");
    ESP_RETURN_ON_ERROR(provisioning_init(), TAG, "provisioning init");
    ESP_RETURN_ON_ERROR(connectivity_manager_init(), TAG, "connectivity init");
    ESP_RETURN_ON_ERROR(remote_service_start(), TAG, "remote service init");
    ESP_RETURN_ON_ERROR(ota_manager_init(), TAG, "ota init");
    ESP_RETURN_ON_ERROR(command_router_init(), TAG, "command router init");
    ESP_RETURN_ON_ERROR(local_api_start(), TAG, "local api start");
    xEventGroupSetBits(s_app.events, APP_EVT_STORAGE_READY);
    return ESP_OK;
}

static esp_err_t start_acquisition(void)
{
    s_app.boot_state = APP_BOOT_ACQUISITION;
    ESP_RETURN_ON_ERROR(ecg_task_start(), TAG, "ecg task start");
    ESP_RETURN_ON_FALSE(ads129x_is_ready(), ESP_ERR_INVALID_STATE, TAG, "ecg device is not ready");
    ESP_RETURN_ON_FALSE(ecg_pipeline_queue() != NULL, ESP_ERR_NO_MEM, TAG, "ecg queue missing");
    xEventGroupSetBits(s_app.events, APP_EVT_ECG_READY | APP_EVT_ACQUIRING);
    ESP_RETURN_ON_ERROR(sensor_manager_init(), TAG, "sensor manager init");
    ESP_RETURN_ON_ERROR(display_manager_init(), TAG, "display init");
    return ESP_OK;
}

static void log_runtime_health(const health_ecg_snapshot_t *health)
{
    char telemetry[196];
    (void)telemetry_format_ecg_health(telemetry, sizeof(telemetry), health);
    ESP_LOGI(TAG, "ecg health %s", telemetry);
}

static void supervisor_task(void *argument)
{
    (void)argument;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        const EventBits_t events = xEventGroupGetBits(s_app.events);
        const health_ecg_snapshot_t health = health_ecg_snapshot();

        if ((events & APP_EVT_ACQUIRING) == 0) {
            continue;
        }

        if (health.valid_samples == s_app.last_valid_samples) {
            ++s_app.consecutive_fault_windows;
        } else {
            s_app.consecutive_fault_windows = 0;
        }
        s_app.last_valid_samples = health.valid_samples;

        if (s_app.consecutive_fault_windows >= 3) {
            ESP_LOGW(TAG, "no new ECG samples for %" PRIu32 " seconds", s_app.consecutive_fault_windows);
            xEventGroupSetBits(s_app.events, APP_EVT_FAULT);
        }

        if ((health.valid_samples % 500U) < 8U) {
            log_runtime_health(&health);
        }
        (void)storage_writer_flush();
        display_manager_refresh();
    }
}

static void log_boot_summary(void)
{
    const EventBits_t bits = xEventGroupGetBits(s_app.events);
    ESP_LOGI(TAG,
             "boot complete: state=%s elapsed_ms=%" PRIu32 " id=0x%02x event_bits=0x%02" PRIx32,
             boot_state_name(s_app.boot_state),
             (uint32_t)((esp_timer_get_time() - s_app.boot_time_us) / 1000),
             ads129x_device_id(),
             (uint32_t)bits);
}

void app_main(void)
{
    s_app = (app_context_t){
        .events = xEventGroupCreate(),
        .boot_state = APP_BOOT_RESET,
        .first_error = ESP_OK,
        .boot_time_us = (uint32_t)esp_timer_get_time(),
    };

    if (s_app.events == NULL) {
        ESP_LOGE(TAG, "cannot create application event group");
        return;
    }

    esp_err_t result = initialise_nvs();
    if (result == ESP_OK) result = initialise_platform();
    if (result == ESP_OK) result = initialise_services();
    if (result == ESP_OK) result = start_acquisition();
    if (result != ESP_OK) {
        record_boot_error(result, boot_state_name(s_app.boot_state));
        return;
    }

    s_app.boot_state = APP_BOOT_RUNNING;
    xTaskCreatePinnedToCore(supervisor_task, "health_supervisor", 4096, NULL, 5,
                            &s_app.supervisor_task, 1);
    if (s_app.supervisor_task == NULL) {
        record_boot_error(ESP_ERR_NO_MEM, "health supervisor");
        return;
    }
    log_boot_summary();
}
