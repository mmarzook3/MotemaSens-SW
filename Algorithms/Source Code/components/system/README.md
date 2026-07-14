# System component map

`health.c` accumulates acquisition-state counters without modifying sample values. `telemetry.c` converts that state into a compact status payload for a display, local endpoint, BLE characteristic, or remote service.
