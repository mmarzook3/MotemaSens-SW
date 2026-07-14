#pragma once
#include <stdbool.h>
#include "esp_err.h"
esp_err_t remote_service_start(void);
bool remote_service_connected(void);
