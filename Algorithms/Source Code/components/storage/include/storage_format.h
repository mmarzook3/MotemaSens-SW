#pragma once

#include <stdint.h>

typedef struct __attribute__((packed)) {
    char magic[8];
    uint16_t header_size;
    uint16_t record_size;
    uint32_t format_version;
    uint32_t start_ms;
    uint8_t channel_mask;
    uint8_t reserved0[3];
    char firmware_version[40];
} ms_binary_header_t;

typedef struct __attribute__((packed)) {
    uint32_t elapsed_ms;
    uint32_t ecg_us;
    uint32_t ecg_seq;
    uint32_t ecg_status;
    int32_t lead_i_raw;
    int32_t lead_ii_raw;
    int32_t lead_iii_raw;
    uint32_t mic_ms;
    uint32_t imu_ms;
    int16_t mic_trace_q15;
    int16_t mic_level_q15;
    int16_t acc_x_mg;
    int16_t acc_y_mg;
    int16_t acc_z_mg;
    int16_t raw_x;
    int16_t raw_y;
    int16_t raw_z;
    uint16_t diagnostic_flags;
    uint8_t ecg_seq8;
    uint8_t lead_off_positive;
    uint8_t lead_off_negative;
    uint8_t saturation_mask;
    uint8_t mic_seq8;
    uint8_t imu_seq8;
    uint8_t imu_diagnostic_flags;
    uint8_t reserved[3];
} ms_binary_record_t;

_Static_assert(sizeof(ms_binary_header_t) == 64, "binary header must remain 64 bytes");
_Static_assert(sizeof(ms_binary_record_t) == 64, "binary record must remain 64 bytes");
