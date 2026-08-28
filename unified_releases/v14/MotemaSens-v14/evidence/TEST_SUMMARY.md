# MotemaSens v14 test summary

Automated and available physical-device gates passed. Publication was explicitly approved with limitations by Mohamed Marzook.

Known validation limitations:

- USB mass storage requires a revised PCB that routes the USB-C connector to the ESP32-S3 native USB pins; current CH343-only hardware uses resumable Local WiFi downloads.
- The v14 bench recording used open ECG electrodes, so physiological ECG morphology and isolated-power versus mains interference were not revalidated in this pass.
- MATLAB runtime was unavailable; packaged MATLAB contracts and fixtures passed, and Python conversion passed on the physical v14 recording.
- The available camera was not pointed at the round LCD, so current-candidate LCD camera evidence was unavailable.

Reason: All requested v14 software, physical device, OTA, transport, SD, backend and Android checks passed. The release workstation and present bench arrangement cannot repeat MATLAB-runtime, isolated physiological ECG, mains-comparison or camera-facing LCD checks.

Evidence: docs/firmware/test_results/2026-08-28-v14-release/README.md.
