#pragma once

#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "ms_types.h"

esp_err_t ecg_pipeline_init(void);
QueueHandle_t ecg_pipeline_queue(void);
bool ecg_pipeline_publish(const ms_ecg_sample_t *sample);
