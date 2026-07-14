#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
typedef enum { LOGGING_IDLE, LOGGING_SD, LOGGING_USB, LOGGING_REMOTE } logging_mode_t;
typedef struct { logging_mode_t mode; uint8_t channel_mask; uint32_t records; uint32_t dropped; } logging_snapshot_t;
esp_err_t logging_manager_init(void);
logging_snapshot_t logging_manager_snapshot(void);
