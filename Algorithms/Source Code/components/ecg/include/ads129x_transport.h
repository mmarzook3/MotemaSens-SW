#pragma once

#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

esp_err_t ads129x_transport_transfer(const uint8_t *tx, uint8_t *rx, size_t bytes);
