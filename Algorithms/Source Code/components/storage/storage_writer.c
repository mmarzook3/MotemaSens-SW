#include "storage_writer.h"
#include "storage_format.h"
#include "ring_buffer.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "storage";
static uint8_t s_write_storage[64 * 256];
static ring_buffer_t s_buffer;

esp_err_t storage_writer_init(void)
{
    ring_buffer_init(&s_buffer, s_write_storage, sizeof(s_write_storage));
    ESP_LOGI(TAG, "binary record size: %u bytes", (unsigned)sizeof(ms_binary_record_t));
    return ESP_OK;
}

esp_err_t storage_writer_append_ecg(const ms_ecg_sample_t *sample)
{
    ms_binary_record_t record = {
        .ecg_us = sample->timestamp_us,
        .ecg_seq = sample->sequence,
        .ecg_status = sample->status_word,
        .lead_i_raw = sample->channels[0],
        .lead_ii_raw = sample->channels[1],
        .lead_iii_raw = sample->channels[1] - sample->channels[0],
        .diagnostic_flags = sample->diagnostic_flags,
        .lead_off_positive = sample->lead_off_positive,
        .lead_off_negative = sample->lead_off_negative,
        .saturation_mask = sample->saturation_mask,
        .ecg_seq8 = (uint8_t)sample->sequence,
    };
    return ring_buffer_write(&s_buffer, (const uint8_t *)&record, sizeof(record)) ? ESP_OK : ESP_ERR_NO_MEM;
}

esp_err_t storage_writer_flush(void)
{
    /* The platform SD/VFS writer drains this buffer in aligned batches. */
    return ESP_OK;
}
