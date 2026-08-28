# MotemaSens gap events

Format-v4 logs use explicit GAP events when samples are known to be missing.
Each event identifies the stream, reason, number of missing samples, expected
sequence and next observed sequence.

| Stream | Nominal sample period |
| --- | --- |
| ECG | 2,000 microseconds |
| MIC | 500 microseconds |
| IMU | 8,000 microseconds |

The v12 Python, Flutter and MATLAB readers expand each event into timestamped
`ECG_MISSING`, `MIC_MISSING`, or `IMU_MISSING` rows. Values remain `NaN`; the
timeline is not compressed and no replacement waveform is generated.

Small reported gaps normally produce `MINOR_LOSS`. Severe loss, failed stream
accounting, write failure, invalid checksum or incomplete structure produces
`FAILED` or `UNVERIFIED`.
