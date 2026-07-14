#pragma once

#include "esp_err.h"

typedef enum {
    MS_STATUS_OK = 0,
    MS_STATUS_NOT_READY,
    MS_STATUS_SPI_FAILURE,
    MS_STATUS_FRAME_INVALID,
    MS_STATUS_QUEUE_FULL,
    MS_STATUS_STORAGE_FAILURE,
} ms_status_t;

esp_err_t ms_status_to_esp_err(ms_status_t status);
