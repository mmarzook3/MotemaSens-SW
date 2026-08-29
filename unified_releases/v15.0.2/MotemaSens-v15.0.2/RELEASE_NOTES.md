# MotemaSens v15.0.2 release notes

MotemaSens v15.0.2 is a unified reliability release for device firmware, the
Android app, desktop tools, documentation and package metadata.

## Software update reliability

- Fixes a firmware startup-order race that could make a valid Local or Remote
  OTA image fail boot-health validation and roll back.
- Holds the Core 1 output task behind an explicit startup barrier until OTA
  health timing and both core-loop baselines are valid.
- Uses a fresh monotonic timestamp and signed elapsed-time check so a stale
  clock value cannot become a false OTA timeout.
- Defers restart requests until a newly installed image completes runtime health
  confirmation.
- Retains the previous system stage and both core-loop counters when a rollback
  is reported, improving diagnosis if a future update cannot start correctly.
- Keeps Local and Remote update operations alive when the Software Update screen
  is closed.
- Restores the same update ID, selected release, status message and progress when
  the Software Update screen is reopened.
- Reports success only after the device restarts on the expected firmware,
  completes runtime health validation, clears `pendingVerify` and reports a zero
  health-failure mask.

## Retained v15 functionality

- Raw, timestamped v4 ECG, microphone and IMU recording.
- Default rates of 500 Hz ECG, 2 kHz microphone and 125 Hz IMU.
- Local IP, BLE and Remote control.
- Smooth Local IP live preview and mobile signal analysis.
- Segmented SD recordings with open, rename, download and delete operations.
- BIN-to-CSV, MATLAB, USB logger and software-updater tools.
- Existing account, provisioning, power-bank and device-control features.

## Validation

- All ten firmware build environments passed.
- Firmware contract suite passed with 124 tests.
- Flutter static analysis passed with no issues.
- Flutter suite passed with 149 tests, including Local and Remote update-state
  restoration after leaving and reopening the screen.
- A source-equivalent development build completed a physical Local WiFi OTA on
  SL2 with all stages at 100%, the expected firmware running,
  `pendingVerify=false`, `healthFailureMask=0` and OTA phase `success`.
- The established Android update-signing identity and all package checksums are
  verified during release packaging.

## Installation

Install the v15.0.2 Android app first. Then open **Software Update** and install
MotemaSens firmware v15.0.2 using Local WiFi or Remote update. Keep the device
powered until the app reports final version and health confirmation.

## Validation limitation

The exact official v15.0.2 APK and firmware are published without installation
on the connected phone or ESP32 devices, as requested. Manual installation and
post-release Local/Remote OTA validation remain pending. The release artifacts
are built from the same source state as the validated development firmware,
with release-version metadata applied.

MotemaSens v15.0.2 remains an engineering and research prototype. Stored raw
signals are not modified to make displayed waveforms look more normal.
