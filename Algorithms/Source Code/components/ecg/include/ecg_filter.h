#pragma once

#include <stdint.h>

typedef struct {
    float baseline;
    float output;
    float scale;
} ecg_display_filter_t;

void ecg_display_filter_reset(ecg_display_filter_t *filter);
float ecg_display_filter_process(ecg_display_filter_t *filter, int32_t lead_i, int32_t lead_ii);
