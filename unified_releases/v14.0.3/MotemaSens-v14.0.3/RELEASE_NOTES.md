# MotemaSens v14.0.3 release notes

MotemaSens v14.0.3 adds checksum-verified VPS firmware caching, faster Remote
OTA downloads and a substantially faster Local WiFi firmware transfer to the
validated v14 device, mobile and transfer-reliability software.
Firmware, Android app, desktop tools, documentation and package metadata use
the same `14.0.3` version.

Highlights:

- Caches the exact approved `firmware.bin` in the persistent MotemaSens VPS
  volume before every official public release.
- Blocks publication when VPS upload, release identity, byte count or SHA-256
  verification fails.
- Uses the VPS cache for normal Remote OTA instead of direct ESP32-to-GitHub
  firmware downloads, while retaining the public repository as repair source.
- Uses direct VPS HTTP for v14+ firmware and an HTTPS compatibility route for
  older OTA-capable firmware.
- Raises only the bounded Remote OTA transfer worker above the Core 1
  presentation task, increases its stream buffer to 8 KB and yields every
  32 KB. Core 0 acquisition priorities remain unchanged.
- Reduced the physical cached-download test for a 1,824,448-byte image to
  28.6 seconds, with reboot and runtime health-confirmed success at 53.6
  seconds total.
- Replaces the previous byte-by-byte 8 KB Local OTA body copy with negotiated
  64 KB HTTP chunks streamed through a fixed 8 KB buffer.
- Retains automatic 8 KB compatibility for devices running older firmware.
- Reduced the physically measured Local transfer stage for a 1,826,096-byte
  image to 26.8 seconds. The complete update, including reboot, WiFi
  reassociation and runtime health confirmation, completed in 57.2 seconds.
- Prevents the app from reporting Local OTA success while the image is still
  in boot verification. Success now requires the expected version,
  `phase=success` and `pendingVerify=false`.
- Reports rollback explicitly if an image appears temporarily and then returns
  to the previous partition.

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
device powered and connected until it restarts and reports firmware `v14.0.3`.

This remains an engineering and research prototype. USB mass storage is not
available on the current CH343-only PCB. Local WiFi remains the supported
recording-download method for that hardware.

The release package was built, signed, checksum-verified and cached on the VPS
without flashing a physical device during publication. Local IP and Remote OTA
installation are intentionally reserved for the requested post-release device
tests.
