#include "health.h"
#include "ecg_diagnostics.h"

static health_ecg_snapshot_t s_ecg;

esp_err_t health_init(void)
{
    s_ecg = (health_ecg_snapshot_t){};
    return ESP_OK;
}

void health_report_ecg(const ms_ecg_sample_t *sample)
{
    ++s_ecg.valid_samples;
    s_ecg.last_sequence = sample->sequence;
    if (sample->saturation_mask) ++s_ecg.saturated_samples;
    if (sample->diagnostic_flags & ECG_DIAG_LEAD_OFF) ++s_ecg.lead_off_samples;
}

void health_report_ecg_fault(void) { ++s_ecg.failed_samples; }

health_ecg_snapshot_t health_ecg_snapshot(void) { return s_ecg; }
