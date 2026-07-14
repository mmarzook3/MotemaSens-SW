#include "ecg_task.h"
#include "ads129x.h"
#include "board_pins.h"
#include "ecg_pipeline.h"
#include "storage_writer.h"
#include "health.h"
#include "driver/gpio.h"
#include "esp_check.h"
#include "esp_log.h"

static TaskHandle_t s_task;
static volatile uint32_t s_drdy_edges;

static void IRAM_ATTR drdy_isr(void *arg)
{
    (void)arg;
    ++s_drdy_edges;
}

static void ecg_task(void *arg)
{
    (void)arg;
    uint32_t processed_edges = 0;
    uint32_t sequence = 0;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        while (processed_edges != s_drdy_edges) {
            ++processed_edges;
            ms_ecg_sample_t sample = {.sequence = ++sequence};
            if (ads129x_read_frame(&sample) == ESP_OK) {
                (void)ecg_pipeline_publish(&sample);
                (void)storage_writer_append_ecg(&sample);
                health_report_ecg(&sample);
            } else {
                health_report_ecg_fault();
            }
        }
    }
}

static void IRAM_ATTR drdy_notify_isr(void *arg)
{
    drdy_isr(arg);
    BaseType_t higher_priority_task_woken = pdFALSE;
    vTaskNotifyGiveFromISR(s_task, &higher_priority_task_woken);
    if (higher_priority_task_woken) portYIELD_FROM_ISR();
}

esp_err_t ecg_task_start(void)
{
    ESP_RETURN_ON_ERROR(ecg_pipeline_init(), "ecg_task", "pipeline");
    ESP_RETURN_ON_ERROR(ads129x_init(), "ecg_task", "initialisation");
    ESP_RETURN_ON_ERROR(ads129x_start_continuous(), "ecg_task", "continuous mode");
    xTaskCreatePinnedToCore(ecg_task, "ecg_acquisition", 6144, NULL, 20, &s_task, 0);
    ESP_RETURN_ON_FALSE(s_task, ESP_ERR_NO_MEM, "ecg_task", "task");
    ESP_RETURN_ON_ERROR(gpio_install_isr_service(ESP_INTR_FLAG_IRAM), "ecg_task", "gpio isr");
    ESP_RETURN_ON_ERROR(gpio_isr_handler_add(BOARD_ECG_DRDY_GPIO, drdy_notify_isr, NULL), "ecg_task", "drdy isr");
    return ESP_OK;
}
