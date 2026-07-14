#pragma once
#include <stdbool.h>
#include <stdint.h>
typedef struct { bool wifi; bool ble; bool remote; bool logging; uint8_t battery_percent; } display_model_t;
display_model_t display_model_current(void);
