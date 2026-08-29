# MotemaSens v15.0.2 test summary

Automated and available physical-device gates passed. Publication was explicitly approved with limitations by Marzook.

Known validation limitations:

- The exact official v15.0.2 firmware image was not flashed to a physical device by explicit request.
- The exact official v15.0.2 APK was not installed on the connected phone by explicit request.
- Manual Local and Remote OTA installation of v15.0.2 remain post-publication tests.
- MATLAB runtime validation remains deferred because MATLAB is unavailable on the release workstation.
- USB mass storage requires revised native-USB hardware; current devices use Local WiFi download.

Reason: Publication was explicitly requested without flashing firmware to the ESP32 devices or installing the official APK. The source-equivalent development firmware passed a complete physical Local WiFi OTA, reboot and runtime health-confirmation test before the release-version freeze.

Evidence: docs/firmware/test_results/2026-08-29-v15.0.2-release/README.md.
