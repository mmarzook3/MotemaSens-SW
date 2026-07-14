#include "ecg_pipeline.h"
#include "ms_config.h"

static QueueHandle_t s_queue;

esp_err_t ecg_pipeline_init(void)
{
    s_queue = xQueueCreate(MS_ECG_QUEUE_DEPTH, sizeof(ms_ecg_sample_t));
    return s_queue ? ESP_OK : ESP_ERR_NO_MEM;
}

QueueHandle_t ecg_pipeline_queue(void) { return s_queue; }

bool ecg_pipeline_publish(const ms_ecg_sample_t *sample)
{
    if (xQueueSend(s_queue, sample, 0) == pdTRUE) return true;
    ms_ecg_sample_t oldest;
    (void)xQueueReceive(s_queue, &oldest, 0);
    return xQueueSend(s_queue, sample, 0) == pdTRUE;
}
