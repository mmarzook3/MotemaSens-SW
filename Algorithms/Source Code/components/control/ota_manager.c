#include "ota_manager.h"
#include <string.h>
static ota_snapshot_t s_ota;
esp_err_t ota_manager_init(void) { memset(&s_ota, 0, sizeof(s_ota)); return ESP_OK; }
ota_snapshot_t ota_manager_snapshot(void) { return s_ota; }
