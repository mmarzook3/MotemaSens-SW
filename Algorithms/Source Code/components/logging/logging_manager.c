#include "logging_manager.h"
static logging_snapshot_t s_log = {.mode = LOGGING_IDLE};
esp_err_t logging_manager_init(void) { return ESP_OK; }
logging_snapshot_t logging_manager_snapshot(void) { return s_log; }
