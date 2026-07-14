#include "ads129x.h"
#include "ecg_diagnostics.h"
#include "ads129x_transport.h"
#include "ms_config.h"
#include "esp_check.h"
#include "esp_timer.h"

static int32_t decode_signed_24(const uint8_t *p)
{
    int32_t value = ((int32_t)p[0] << 16) | ((int32_t)p[1] << 8) | p[2];
    return (value & 0x00800000) ? (value | 0xFF000000) : value;
}

esp_err_t ads129x_read_frame(ms_ecg_sample_t *sample)
{
    uint8_t tx[MS_ECG_FRAME_BYTES] = {};
    uint8_t rx[MS_ECG_FRAME_BYTES] = {};
    ESP_RETURN_ON_ERROR(ads129x_transport_transfer(tx, rx, sizeof(tx)), "ads129x", "frame transfer");
    sample->timestamp_us = (uint32_t)esp_timer_get_time();
    sample->status_word = ((uint32_t)rx[0] << 16) | ((uint32_t)rx[1] << 8) | rx[2];
    for (uint8_t channel = 0; channel < MS_ECG_CHANNEL_COUNT; ++channel) {
        sample->channels[channel] = decode_signed_24(&rx[3 + channel * 3]);
    }
    sample->valid = true;
    ecg_diagnostics_update(sample);
    return ESP_OK;
}
