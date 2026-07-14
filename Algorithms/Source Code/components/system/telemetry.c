#include "telemetry.h"
#include <stdio.h>

size_t telemetry_format_ecg_health(char *buffer, size_t buffer_size, const health_ecg_snapshot_t *health)
{
    return (size_t)snprintf(buffer, buffer_size,
        "{\"ecg_samples\":%lu,\"ecg_failed\":%lu,\"ecg_saturated\":%lu,\"ecg_lead_off\":%lu,\"ecg_sequence\":%lu}",
        (unsigned long)health->valid_samples,
        (unsigned long)health->failed_samples,
        (unsigned long)health->saturated_samples,
        (unsigned long)health->lead_off_samples,
        (unsigned long)health->last_sequence);
}
