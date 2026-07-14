#include "power_manager.h"
static power_snapshot_t s_power;
esp_err_t power_manager_init(void) { return ESP_OK; }
power_snapshot_t power_manager_snapshot(void) { return s_power; }
