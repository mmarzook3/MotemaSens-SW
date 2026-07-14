#include "ecg_diagnostics.h"
#include "ms_config.h"
#include <stdlib.h>

void ecg_diagnostics_update(ms_ecg_sample_t *sample)
{
    sample->diagnostic_flags = ECG_DIAG_RLD_ENABLED | ECG_DIAG_LEAD_OFF_ON;
    sample->saturation_mask = 0;
    for (unsigned channel = 0; channel < MS_ECG_ACTIVE_LEADS - 1; ++channel) {
        if (labs(sample->channels[channel]) >= MS_ECG_SATURATION_LIMIT) {
            sample->saturation_mask |= 1U << channel;
        }
    }
    if (sample->saturation_mask) sample->diagnostic_flags |= ECG_DIAG_DC_SATURATION;
    if (sample->lead_off_positive || sample->lead_off_negative) sample->diagnostic_flags |= ECG_DIAG_LEAD_OFF;
}
