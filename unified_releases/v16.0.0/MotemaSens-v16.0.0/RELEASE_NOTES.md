# MotemaSens v16.0.0

Unified firmware, Android app and analysis-tools release for field testing.
Software validation completed; no physical device was available for this batch.
Physical OTA, sleep/wake, acoustic playback and thermal validation are pending.

## Changes

- Live ECG selector for Leads I, II and III. Firmware sends synchronized raw
  Lead I and II; Lead III is calculated as II-I. Display filtering stays linear.
- ECG, microphone and IMU graphs are grouped together before analysis panels.
- Microphone-only PCG analysis works without an ECG history. Timestamp-based
  startup replaces fixed sample counts; IMU gaps no longer reset PCG history.
- Listening switch for Android headphone monitoring during Local IP live view.
  Audio uses a bounded buffer and stops on exit/background. Saved raw data is
  independent of playback. No acoustic diagnosis is implied.
- Sleep action in Local, BLE and Remote controls. It rejects active recording,
  storage work or firmware updates. Wake with RESET or a complete power cycle.
  Sleep is not an electrical battery disconnect.
- Internal IMU temperature displayed when supplied by the device. This is not
  enclosure or skin-contact temperature and cannot establish thermal safety.
- HTTP command rejection/busy replies are surfaced rather than reported as
  successful commands merely because the HTTP status is 200.
- Original timestamped SD data, existing rename/delete, remembered IP and
  reset/watchdog diagnostics remain available.
- Phone captures additionally retain raw I/II and export ECG_I/II/III CSV rows.

## Compatibility and installation

1. Install `motemasens-mobile-v16.0.0.apk` first.
2. Connect to the device, open Software Update and select v16.0.0.
3. Keep power and network available through transfer, reboot and health check.
4. Confirm app 16.0.0 and firmware v16.0.0.

The new app accepts legacy MSLV v1 and v2 live streams. Previous apps cannot
decode the new three-lead v2 stream. Older firmware displays a labelled legacy
I-II trace without a lead selector. SD binary format remains v4.

Use the included FIELD_TESTS.md to report results against GitHub issues #1-#5.
Heat, electrode contact, acoustic coupling and silicone/adhesion issues remain
open. Existing acoustic candidate heuristics need clinician-reviewed recordings
and must not be interpreted as confirmed murmurs, rubs or mechanical valves.
