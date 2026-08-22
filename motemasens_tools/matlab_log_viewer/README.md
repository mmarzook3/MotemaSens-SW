# MotemaSens MATLAB log reader

`read_motemasens_log.m` reads MotemaSens CSV files and SD binary logs in formats
v1, v2, v3 and v4. Keep `read_motemasens_v4.m` in the same folder; it provides
the verified independent-stream v4 decoder.

```matlab
[T, info] = read_motemasens_log('log_123456.bin');
```

For v4 logs, `info.quality` is `complete`, `minor_loss`, `failed`, or
`unverified`. `info.crcValid`, `info.gapSamples`, and
`info.sessionDiagnostics` explain the result. Only
`info.timingReady == true` is suitable for precise cross-sensor timing.

The v4 event table uses `ecg_ch1_raw` through `ecg_ch4_raw`. It provides
`lead_i`, `lead_ii`, and `lead_iii_derived = lead_ii - lead_i`. Raw channel 3
is not Lead III. Microphone blocks are expanded into individual 2 kHz samples.
Missing samples appear as timestamped `<stream>_MISSING` rows, and invalid
acquisition values remain `NaN`.

`T` contains the ECG, microphone and IMU columns. For v3 recordings it also includes microphone validity, missing-sample reason, IMU validity, IMU age and IMU sample sequence.

`info` reports the binary format and whether a v3 clean-stop trailer was found.
For v3, incomplete microphone samples remain explicitly marked in `T`; they are
not replaced with zero-valued audio. Use the supplied Python BIN-to-CSV converter
when CRC32 verification is required; MATLAB reports trailer presence and
record-count consistency, while the Python converter verifies the payload CRC32
and reports the recorded session microphone source-gap total. Updated v3
trailers also expose ECG received/invalid/overrun and signal-condition counters,
plus the recording-start configuration/readback state through `info.trailer`.
They also expose IMU missed-update and failed-poll totals. In the record table,
an IMU entry with `imuValid = 0`, retained age/sequence fields, and
`accDiagFlags` bit `0x10` is a stale value rather than a fresh IMU sample.

## Regression fixture pack

`fixtures/phase7/` contains small synthetic v1, v2 and v3 recordings for checking this reader. The v3 fixture includes explicit lead-off, saturation, invalid-frame/overrun, microphone-gap and stale-IMU conditions. See [fixtures/phase7/README.md](fixtures/phase7/README.md) for the expected result of each file.
