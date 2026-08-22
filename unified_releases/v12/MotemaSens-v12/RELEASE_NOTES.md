# MotemaSens v12 release notes

MotemaSens v12 is the first unified release: firmware, Android app, desktop
tools, documentation and package metadata all use the same version.

Highlights:

- Recording start/stop is acknowledged by the acquisition core before the app
  reports success.
- SD browsing and software updates are locked during recording.
- Session diagnostics include queue, stall, SD and stream-boundary evidence.
- Recordings receive one quality result: complete, minor loss, failed or
  unverified.
- Python, Flutter and MATLAB readers share the same v4 channel, gap, checksum
  and quality rules.
- Raw ECG channels are clearly named and Lead III is derived as Lead II minus
  Lead I.
- Invalid and missing values remain visible as `NaN` rather than being hidden.
- The phone live view now renders smooth ECG, heart-sound microphone and IMU
  waveforms without changing the raw values saved to the SD card.
- Local-IP streaming remains responsive while SD recording is active, with
  bounded history and explicit connection, pause and error states in the app.
- Firmware, Android app, BIN-to-CSV, MATLAB viewer, USB logger, updater and user
  documentation are supplied together as one versioned package.

Automated builds, parser tests, Android emulator checks and connected-phone,
ESP32, SD, BLE, OTA, USB and live-preview tests passed. MATLAB runtime execution
and an isolated-power ECG morphology test were not available in this release
environment; this release is therefore published with those validation
limitations recorded, rather than reported as passed.
