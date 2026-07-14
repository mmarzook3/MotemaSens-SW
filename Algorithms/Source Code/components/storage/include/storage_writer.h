#pragma once

#include "esp_err.h"
#include "ms_types.h"

esp_err_t storage_writer_init(void);
esp_err_t storage_writer_append_ecg(const ms_ecg_sample_t *sample);
esp_err_t storage_writer_flush(void);
