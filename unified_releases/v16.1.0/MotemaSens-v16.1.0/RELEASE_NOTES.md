# MotemaSens v16.1.0 - Local WiFi preview stall correction

Unified firmware, Android app and tools release. Intended for Ernest's field
retest of the reproducible v16 Local WiFi preview stalls. No physical MotemaSens
device was available; the hardware acceptance checks below remain pending.

## Firmware changes

- Dedicated preview task runs independently of the shared display/SD/cloud
  output loop. Background-network busy flags no longer suspend preview sending.
- Acquisition writes into protected preview buffers before storage queues.
- Nonblocking TCP sends retain partial frames and advance cursors only after
  complete transmission. The worker yields between attempts.
- Normal 20 ms target cadence plus bounded faster backlog recovery.
- At least 8.192 seconds of preview history at supported maximum sensor rates.
  Pauses beyond retention still produce explicit gaps; no samples are invented.
- Separate polling/stream output buffers and protected client handoff.
- Additional gap, socket backpressure, timeout, snapshot-duration and worker
  stack diagnostics. Automatic OTA checks are deferred while preview is active.

MSLV v2 layout, raw values, acquisition settings and SD format are unchanged.
App 16.1.0 retains the Save/Share/Downloads fix from 16.0.1. Tools include a new
read-only `preview_stream_probe.py` in the USB logger folder (it uses WiFi).

## Validation

Actual old/new C++ transport code was compiled and run with simulated clocks,
sensor inputs and sockets in a local isolated container. Six 3.08-second stalls
reproduced six gap events on v16. Revised transport delivered all 15,000 ECG,
60,000 MIC and 3,750 IMU samples from a 30-second default-rate acquisition,
including worker stalls and partial/socket-stalled writes. Maximum-rate tests
delivered all 60,000 / 60,000 / 7,500 samples. Recovery to within 40 ms of current
source data took at most 582 ms at default rates and 1490 ms at maximum rates.

Concurrency, sequence wrap, over-capacity gap reporting and no-progress timeout
were tested. A 12-second over-capacity stall correctly reported loss. These are
transport simulations, not measured ESP32 WiFi/FreeRTOS performance.

## Update and retest

Install the included Android app first, then use Software Update to install
firmware v16.1.0. Keep power connected through reboot/health confirmation.
No automatic flash to local devices was performed during this release.

On Windows with Python installed, run from the tools/usb_logger directory:

```text
python preview_stream_probe.py --base-url http://DEVICE_IP --duration 30 --output preview-30s.json
python preview_stream_probe.py --base-url http://DEVICE_IP --duration 300 --output preview-5min.json
```

Replace DEVICE_IP with the patch's IP. Run two 30-second captures, then the
five-minute test, first idle and then with SD logging/cloud activity. The probe
does not start/stop recording. Report JSON results, firmware/app version and power
source. At default rates expect continuity, no sequence/cursor gaps or duplicates,
and packet cadence approaching 20 ms on an uncongested link (p95 target <40 ms).
Inspect `phonePreviewSnapshotMaxUs` and task stack margin alongside acquisition
overrun/drop counters. Missing/invalid acquisition data remain separate issues.

Packet arrival timestamps are not physiological sample timestamps. Preserve
raw recordings; physical signal quality, heating and acoustic coupling are not
resolved by this transport correction.
