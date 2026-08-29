# MotemaSens v15.0.0

MotemaSens records ECG, heart-sound microphone and motion data. This repository contains released software, tools and user documentation.

## Downloads

- [Android app v15.0.0](https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/mobile_releases/v15.0.0/motemasens-mobile-v15.0.0.apk)
- [Device firmware v15.0.0](https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/releases/v15.0.0/firmware.bin)
- [Complete v15.0.0 package](https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/unified_releases/v15.0.0/MotemaSens-v15.0.0.zip)

Update the Android app first, then update device firmware from the app.

## Validation status

This release passed automated and available connected-device checks. It was published with the following recorded validation limitations:

- The exact v15.0.0 firmware image was not flashed to a physical device by explicit request.
- Local and Remote OTA installation of the exact public v15.0.0 firmware remain post-publication tests.
- MATLAB runtime validation remains deferred because MATLAB is unavailable on the release workstation.
- USB mass storage requires revised native-USB hardware; current devices use Local WiFi download.

# MotemaSens v15.0.0 user guide

MotemaSens records ECG, heart-sound microphone and motion data. The Android app
controls recording, displays status, manages SD files and updates the device.

## Connection modes

- **BLE**: device discovery, WiFi setup, status and basic control.
- **Local**: full control when phone and device use the same WiFi network.
- **Remote**: account-based control when the device is online.

The device display shows the complete local IP address. Enter it in Local mode
exactly as shown. A connected WiFi indicator does not mean the phone is on the
same network; confirm the phone WiFi name if Local mode cannot connect.

## Recording to SD

1. Confirm the SD status is ready.
2. Open **Storage** in the app.
3. Select ECG, MIC, IMU, or all signals.
4. Start **Write to SD card**.
5. Wait for the app and device to show recording.
6. Stop the recording and wait for verification to finish.

SD browsing and software updates are intentionally locked while recording.
After stopping, refresh the file list to download, rename or delete a recording.

## Recording result

- **COMPLETE**: structure, checksum and stream accounting passed.
- **MINOR LOSS**: usable for some review, but contains a reported warning or
  small gap. Review the diagnostics before analysis.
- **FAILED**: do not use for timing or waveform interpretation.
- **UNVERIFIED**: the recording did not finish with enough evidence to prove it
  complete.

Missing samples remain missing. The tools do not invent, repeat or interpolate
sensor values to hide a gap.

## Working with files

Binary `.bin` files are the original high-speed recordings. Keep the original
file and convert a copy to CSV when needed. The v15.0.0 package contains:

- BIN-to-CSV graphical and command-line tools.
- MATLAB log reader.
- USB logger for direct PC captures.
- Software updater for USB recovery and released firmware installation.

Use Local WiFi to download SD recordings on the current device. The app may
show USB file-transfer capability, but it remains unavailable on CH343-only
hardware. USB mass storage requires a later hardware revision with ESP32-S3
native USB data lines routed to the connector.

## Software updates

Install the v15.0.0 Android app first. In the app, open **Software Update**, select
MotemaSens v15.0.0, and keep the device powered and connected until it restarts and
reports firmware `v15.0.0`. A successful upload is not final confirmation; the
version shown after reboot is the confirmation.

## Safe use

MotemaSens v15.0.0 is an engineering and research prototype. A recording-quality
result describes file integrity and detected signal conditions; it is not a
medical diagnosis. Follow the approved study and electrode-placement procedure.

## Report an issue

Use the [GitHub issue tracker](https://github.com/mmarzook3/MotemaSens-SW/issues) and include the app version, device version, steps, and a screenshot where possible.
