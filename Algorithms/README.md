# MotemaSens Algorithms

This folder contains public algorithm specifications and small reference tools used to review MotemaSens recordings.

It is intended to make the data path understandable and reproducible without publishing the private device firmware or mobile-app source code.

## Available Algorithms

- [ECG acquisition and logging](ECG/README.md)
- [ECG recording review](ECG/recording-review-2026-07-13.md)
- [ECG binary-log validator](ECG/ecg_log_validator.py)

The validator uses only Python’s standard library. It checks the binary header, record alignment, ECG sequence continuity, timestamp spacing, lead-off flags, and saturation flags.
