#pragma once

#include "esp_err.h"
#include "ms_types.h"

typedef struct {
    uint32_t valid_samples;
    uint32_t failed_samples;
    uint32_t saturated_samples;
    uint32_t lead_off_samples;
    uint32_t last_sequence;
} health_ecg_snapshot_t;

esp_err_t health_init(void);
void health_report_ecg(const ms_ecg_sample_t *sample);
void health_report_ecg_fault(void);
health_ecg_snapshot_t health_ecg_snapshot(void);
