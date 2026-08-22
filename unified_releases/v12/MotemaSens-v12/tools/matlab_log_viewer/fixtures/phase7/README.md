# Phase 7 MATLAB fixture pack

This pack provides small synthetic MotemaSens recordings for checking `read_motemasens_log.m`. They are not clinical or physiological recordings.

Open any file in MATLAB from this folder, for example:

```matlab
[T, info] = read_motemasens_log('synthetic-v3-diagnostics.bin');
```

| File | Expected result |
| --- | --- |
| `synthetic-v1.bin` | One legacy ECG/IMU record. |
| `synthetic-v2.bin` | One record with four sequential microphone samples. |
| `synthetic-v3-diagnostics.bin` | Four records: normal data, lead-off, saturation, then an invalid ECG status (`A00000`) with an acquisition-overrun flag, microphone source gap and invalid/stale IMU state. |

For the v3 fixture, preserve missing microphone blocks as marked data. Do not remove them, insert silence, or compress time. The included trailer is a valid clean-stop diagnostic summary. Use the Python converter when CRC32 validation is required.
