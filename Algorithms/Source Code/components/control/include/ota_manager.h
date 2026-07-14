#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
typedef struct { bool active; uint8_t progress; char target_version[40]; } ota_snapshot_t;
esp_err_t ota_manager_init(void);
ota_snapshot_t ota_manager_snapshot(void);
