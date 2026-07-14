#include "ecg_filter.h"
#include <math.h>

void ecg_display_filter_reset(ecg_display_filter_t *filter)
{
    *filter = (ecg_display_filter_t){.scale = 3500.0f};
}

float ecg_display_filter_process(ecg_display_filter_t *filter, int32_t lead_i, int32_t lead_ii)
{
    const float input = (float)(lead_i - lead_ii);
    filter->baseline += 0.010f * (input - filter->baseline);
    filter->output += 0.16f * ((input - filter->baseline) - filter->output);
    filter->scale = fmaxf(1200.0f, fmaxf(filter->scale * 0.997f, fabsf(filter->output) * 2.4f));
    return fmaxf(-0.95f, fminf(0.95f, filter->output / filter->scale));
}
