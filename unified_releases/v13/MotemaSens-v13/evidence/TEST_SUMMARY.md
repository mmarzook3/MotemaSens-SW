# MotemaSens v13 test summary

Automated and available physical-device gates passed. Publication was explicitly approved with limitations by Marzook.

Known validation limitations:

- MATLAB runtime execution was not performed because MATLAB is not installed in the release environment; the static MATLAB cross-reader contract passed.

Reason: The firmware, Android app, physical ESP32, Local OTA, maximum-rate SD recording, clean-stop verification and Python/Flutter readers were tested. MATLAB is not installed in the release environment, so only its static cross-reader contract could be validated.

Evidence: docs/firmware/test_results/2026-08-27-s3-reliability-v13.
