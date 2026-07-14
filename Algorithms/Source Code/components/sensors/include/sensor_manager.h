#pragma once
#include <stdbool.h>
#include "esp_err.h"
typedef struct { bool microphone_ready; bool imu_ready; bool ecg_ready; } sensor_snapshot_t;
esp_err_t sensor_manager_init(void);
sensor_snapshot_t sensor_manager_snapshot(void);
