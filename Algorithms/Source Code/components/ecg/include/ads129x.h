#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "ms_types.h"

esp_err_t ads129x_init(void);
esp_err_t ads129x_start_continuous(void);
esp_err_t ads129x_read_frame(ms_ecg_sample_t *sample);
bool ads129x_is_ready(void);
uint8_t ads129x_device_id(void);
