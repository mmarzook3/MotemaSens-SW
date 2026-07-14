#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
typedef struct { bool battery_present; bool charging; uint16_t millivolts; uint8_t percent; } power_snapshot_t;
esp_err_t power_manager_init(void);
power_snapshot_t power_manager_snapshot(void);
