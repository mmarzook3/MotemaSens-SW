# MotemaSens v15.0.0 test summary

Automated and available physical-device gates passed. Publication was explicitly approved with limitations by Marzook.

Known validation limitations:

- The exact v15.0.0 firmware image was not flashed to a physical device by explicit request.
- Local and Remote OTA installation of the exact public v15.0.0 firmware remain post-publication tests.
- MATLAB runtime validation remains deferred because MATLAB is unavailable on the release workstation.
- USB mass storage requires revised native-USB hardware; current devices use Local WiFi download.

Reason: Publication was explicitly requested without flashing the v15 firmware. The exact signed v15 app was installed on the connected phone, and source-equivalent firmware passed the available connected-device checks before the version-only release freeze.

Evidence: docs/firmware/test_results/2026-08-29-v15.0.0-release/README.md.
