# MotemaSens v12 test summary

Automated and available physical-device gates passed. Publication was explicitly approved with limitations by Mohamed Marzook.

Known validation limitations:

- MATLAB runtime execution was not performed because MATLAB is not installed in the release environment; the static MATLAB cross-reader contract passed.
- Isolated battery-power ECG morphology and signal-quality validation was not performed because the connected device has no battery or electrodes.

Reason: The release owner requested publication for formal field validation. Automated, package, connected-phone, emulator, ESP32, SD, BLE, OTA, USB and live-preview checks passed; unavailable environmental checks remain explicitly deferred.

Evidence: docs/firmware/test_results/2026-08-22-v12-physical and docs/firmware/test_results/2026-08-22-live-phone-preview.
