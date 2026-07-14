#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t timestamp_us;
    uint32_t sequence;
    uint32_t status_word;
    int32_t channels[4];
    uint8_t lead_off_positive;
    uint8_t lead_off_negative;
    uint8_t saturation_mask;
    uint16_t diagnostic_flags;
    bool valid;
} ms_ecg_sample_t;
