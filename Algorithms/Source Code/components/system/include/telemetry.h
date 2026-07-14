#pragma once

#include <stddef.h>
#include "health.h"

size_t telemetry_format_ecg_health(char *buffer, size_t buffer_size, const health_ecg_snapshot_t *health);
