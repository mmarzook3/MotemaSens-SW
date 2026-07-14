#pragma once

#include "ms_types.h"

#define ECG_DIAG_LEAD_OFF        0x0001
#define ECG_DIAG_DC_SATURATION   0x0002
#define ECG_DIAG_CABLE_NOISE     0x0004
#define ECG_DIAG_RLD_UNSTABLE    0x0008
#define ECG_DIAG_RLD_ENABLED     0x0010
#define ECG_DIAG_LEAD_OFF_ON     0x0020

void ecg_diagnostics_update(ms_ecg_sample_t *sample);
