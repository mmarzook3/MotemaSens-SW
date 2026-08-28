# MotemaSens v14 release notes

MotemaSens v14 is a unified device, mobile and transfer-reliability release.
Firmware, Android app, desktop tools, documentation and package metadata use
the same `14.0.0` version.

Highlights:

- Adds the device-first mobile home screen with saved-device discovery and
  automatic Local IP, BLE and Remote fallback.
- Keeps account device lists synchronized while preserving guest devices and
  local settings.
- Adds reliable Local, BLE and Remote controls for WiFi, sample rates, power
  bank always-on mode, recording, OTA and hardware-gated USB file transfer.
- Adds a read-only USB mass-storage architecture with safe eject, timeout,
  write rejection and exclusive SD ownership. Current CH343-only hardware
  reports this capability as unavailable; native USB requires revised routing.
- Improves Local WiFi recording downloads using 20 MHz SD access, 32 KiB DMA
  reads, larger TCP batches, longer progress timeouts and unchanged resumable
  HTTP Range support.
- Improves average tested Local download throughput by approximately 44%, from
  163.9 KB/s to 236.3 KB/s, while eliminating the observed incomplete transfer.
- Preserves exact file bytes across complete and resumed Range downloads.
- Keeps ECG, microphone and IMU logging complete while downloading a closed
  segment: zero source gaps, queue drops, SD drops or write failures in the
  validation run.
- Adds segmented multi-day recording structure, clean-stop verification,
  incomplete-file recovery and resumable phone/cloud synchronization metadata.
- Fixes USB serial live logging start/stop timing and command framing.
- Adds watchdog-safe session catalog scans and expanded system diagnostics.
- Makes OTA boot confirmation deterministic by validating local tasks, sensors
  and memory before cloud reconnection, then requiring a health-confirmed
  `success` state before the app reports the update complete.
- Preserves raw ECG, microphone and IMU data. Display and mobile analysis remain
  derived processing paths and do not alter stored samples.
- Supplies firmware, signed Android APK, BIN-to-CSV, MATLAB viewer, USB logger,
  updater and user documentation together in one package.

Update the Android app first, then update device firmware from the app. Keep the
device powered and connected until it restarts and reports firmware `v14.0.0`.

This remains an engineering and research prototype. USB mass storage is not
available on the current CH343-only PCB. Local WiFi remains the supported
recording-download method for that hardware.
