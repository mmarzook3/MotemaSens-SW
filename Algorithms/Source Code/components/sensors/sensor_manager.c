#include "sensor_manager.h"
#include "microphone_service.h"
#include "imu_service.h"
#include "ads129x.h"
static sensor_snapshot_t s_sensors;
esp_err_t sensor_manager_init(void)
{
    s_sensors.microphone_ready = microphone_service_init() == ESP_OK;
    s_sensors.imu_ready = imu_service_init() == ESP_OK;
    s_sensors.ecg_ready = ads129x_is_ready();
    return ESP_OK;
}
sensor_snapshot_t sensor_manager_snapshot(void) { return s_sensors; }
