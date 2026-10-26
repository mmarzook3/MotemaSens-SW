# MotemaSens v16.2.0 - Reliability and Diagnostic Evidence

Unified firmware, Android app (16.2.0+115) and tools. Published at Marzook's
explicit request for Ernest's hardware testing. Automated checks passed;
physical ESP32/WiFi/SD/OTA testing of this revision is NOT completed.

## Changes

- Deadline-based preview scheduling avoids accumulating processing time after
  each nominal 20 ms period. This is not a hard real-time WiFi guarantee.
- Separate startup/steady timing, timestamped events, backlog age/depth,
  task-heartbeat and mutex-contention diagnostics.
- Five-second absolute partial-frame deadline; incomplete frames never advance
  cursors. Pauses beyond finite retention still report explicit gaps.
- Bounded MQTT writes and complete-packet staging; malformed packet bounds are
  checked before library parsing. Command ACKs are queued safely, with reconnect
  backoff, WiFi-loss reset and protection against task-creation retry loops.
- Fixed SD flush false-success for closed files with pending bytes.
- Bounded ECG integrity evidence: status prefix and SPI/DRDY timing, not samples.
- Android diagnostics include new counters and bounded event evidence with
  privacy filtering. No passwords, NVS or raw signals are uploaded.
- Tools retain BIN v4/MSLV v2 support and the independent WiFi preview probe.

Raw ECG/MIC/IMU values, calibration, lead derivation and binary layouts remain
unchanged. No algorithm suppresses measured T waves.

## Validation and Limits

Actual C++ transport tests retained all expected samples through repeated 3.08 s
stalls, a 3.993339 s stall, repeated 850.264 ms delays and 62.2/125.2 ms jitter,
including maximum rates. Clock/sequence wrap, partial writes, over-capacity gaps
and deadlines were checked. The actual PubSubClient 2.8 library was tested with
the adapter. ACK-size and SD closed-handle failures were reproduced and corrected.
137 firmware checks, 168 Flutter tests and 18 backend tests passed in development.

The previous five invalid ECG frames are NOT claimed physically fixed. The
physical cause of the 3.993-second interval still needs hardware/event evidence.
Simulations do not emulate RF, FreeRTOS, SPI electrical integrity, SD power loss
or runtime memory headroom. MATLAB runtime remains deferred. These results do
not establish clinical performance.

MQTT reconnection following connection loss during SD logging still waits for
session stop. Verify this limitation against the intended long-duration remote
workflow before participant use.

## Update and Test

1. Install Android 16.2.0 first, retaining existing app data.
2. Sign in, select the device, and use Software Update to install v16.2.0.
3. Keep power and WiFi connected until restart and version confirmation.
4. Repeat two independent 30-second MSLV captures, then five minutes, first idle
   and then with simultaneous SD logging and normal cloud activity.
5. Send diagnostics before/after each test. Share report IDs, duration, power
   source, sample rates, sequence/gap results and raw recordings.
6. Check invalid ECG frames, MQTT aborts, backlog/timing events and heap/stack
   margins. Do not filter away or modify raw acquisition evidence.

From tools/usb_logger:

```text
python preview_stream_probe.py --base-url http://DEVICE_IP --duration 30 --output preview-30s.json
python preview_stream_probe.py --base-url http://DEVICE_IP --duration 300 --output preview-5min.json
```

Packet delivery timing is not the physiological sample clock. Finite buffers
cannot prevent loss through indefinite outages. No device was automatically
flashed as part of this release.
