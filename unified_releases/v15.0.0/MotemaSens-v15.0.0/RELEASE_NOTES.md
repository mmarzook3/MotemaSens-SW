# MotemaSens v15.0.0 release notes

MotemaSens v15.0.0 is the official baseline immediately before the planned
firmware optimisation programme. Firmware, Android app, desktop tools,
documentation and package metadata use the unified `15.0.0` version.

Highlights:

- Keeps ECG, microphone and IMU acquisition independent, timestamped and stored
  as raw v4 streams with explicit validity, sequence and gap metadata.
- Retains the validated default rates of 500 Hz ECG, 2 kHz microphone and
  125 Hz IMU.
- Adds a persistent 20 ms Local IP binary preview stream with bounded reconnect
  handling and unchanged recording data.
- Adds a paced mobile jitter buffer so normal WiFi bursts do not make the live
  waveform pause or jump.
- Moves PCG and signal-quality analysis off the Flutter UI isolate so analysis
  cannot block waveform rendering.
- Defers full cloud status and remote SD synchronization while Local preview is
  active, while preserving the lightweight VPS heartbeat.
- Presents the live-view controls in one compact row on the mobile app.
- Adds Open, Rename and Delete controls for segmented SD recording sessions.
- Renames the real session directory on the device SD card and verifies that
  its index and binary segments remain readable under the new name.
- Deletes the complete selected session and all of its segments only after
  confirmation.
- Blocks SD rename/delete during active recording or cloud SD synchronization.
- Prefills the rename dialog with the current visible recording name so small
  filename edits do not require retyping the complete name.
- Clears stale status paths after an SD session is renamed or deleted.
- Preserves existing Local IP, BLE, Remote, OTA, SD, USB logging, account,
  provisioning, power-bank and device-control functionality.
- Includes the signed Android APK, firmware binaries, checksums, BIN-to-CSV,
  MATLAB reader, USB logger, software updater and user documentation in one
  package.

Validation completed before the version freeze includes:

- All ten firmware build environments passed after the SD session-management
  implementation.
- The complete Flutter test suite passed with 147 tests.
- Local live view ran on a connected Samsung for more than seven minutes with
  no device packet gaps, cursor gaps, app drops or acquisition queue drops.
- An all-channel SD recording completed with verified trailer, zero source gaps,
  zero queue drops and zero SD write failures while Local preview was active.
- Segmented recordings were physically created, renamed, reopened and deleted
  from the connected phone and the device SD card.

Install the v15.0.0 Android app first, then update firmware from the app. Keep
the device powered and connected until it restarts and reports firmware
`v15.0.0` with successful runtime health confirmation.

Publication limitation:

- The exact v15.0.0 firmware image is intentionally not flashed to a physical
  device during publication, as requested. It is built and packaged from the
  source-equivalent development firmware that passed the connected-device
  checks above.
- Final Local and Remote OTA installation of the public v15.0.0 firmware remains
  a post-publication test.
- MATLAB runtime validation remains deferred on the release workstation.
- USB mass storage still requires native ESP32-S3 USB routing; current CH343
  hardware continues to use Local WiFi for recording downloads.

MotemaSens v15.0.0 remains an engineering and research prototype. Stored raw
signals are not modified to make displayed waveforms look more normal.
