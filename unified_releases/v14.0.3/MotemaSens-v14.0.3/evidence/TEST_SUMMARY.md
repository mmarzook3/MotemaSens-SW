# MotemaSens v14.0.3 test summary

Automated and available physical-device gates passed. Publication was explicitly approved with limitations by Marzook.

Known validation limitations:

- The exact v14.0.3 firmware and app package were not installed on physical devices before publication by explicit request.
- The same Local OTA implementation was physically validated on SL02 immediately before the version metadata bump, but the final public Local IP test remains pending.
- The same VPS-cached Remote OTA implementation was physically validated on both serialized devices immediately before this release line, but the final public Remote test remains pending.
- MATLAB runtime validation remains deferred because MATLAB is unavailable on the release workstation.
- USB mass storage still requires revised native-USB hardware; current devices use Local WiFi download.

Reason: Publication was explicitly requested without flashing devices. Local IP and Remote OTA installation of the exact public package will be performed after publication.

Evidence: docs/firmware/test_results/2026-08-28-v14.0.3-release/README.md.
