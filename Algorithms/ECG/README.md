# ECG Acquisition And Logging Algorithm

This document describes the public reference algorithm for the ECG data path used by the current MotemaSens engineering release. It is an algorithm description, not the private firmware source code.

## Data Path

```text
ECG ADC conversion
        |
        | DRDY falling edge
        v
SPI frame read
        |
        | 3 status bytes + 4 channels x 3 bytes
        v
24-bit signed conversion
        |
        v
Diagnostic checks
        |
        v
Acquisition queue
        |
        +--> USB / WiFi live output
        +--> display and status processing
        +--> 64-byte SD record writer
```

## 1. Initialisation

The ECG device is initialised in this order:

1. Set chip-select, reset, power-down, start, and data-ready pins to safe states.
2. Start the ECG SPI bus in the configured mode and speed.
3. Wake and reset the ECG converter.
4. Stop continuous data mode while registers are configured.
5. Read and validate the device identification register.
6. Configure high-resolution conversion at the target 500 samples per second.
7. Enable the required ECG input channels and power down unused channels.
8. Configure the reference, right-leg-drive, and optional lead-off diagnostics.
9. Attach the falling-edge interrupt to DRDY.
10. Start conversions and continuous read mode.

The device must not be treated as ECG-ready until the identification read and register readback succeed.

## 2. DRDY And SPI Frame Handling

The DRDY interrupt performs only one lightweight operation: increment an acquisition-edge counter. It does not perform SPI transfers or file writes.

The acquisition loop observes the counter. When a new edge is present and the minimum frame interval has elapsed, it reads one complete frame:

```text
bytes 0..2   status word, big-endian 24-bit
bytes 3..5   channel 1, big-endian signed 24-bit
bytes 6..8   channel 2, big-endian signed 24-bit
bytes 9..11  channel 3, big-endian signed 24-bit
bytes 12..14 channel 4, big-endian signed 24-bit
```

The frame must be read as one SPI transaction with chip select held low for the complete frame. A partial frame must be rejected rather than written as a valid sample.

The acquisition loop also records a microsecond timestamp and increments a full-width ECG sequence number. A separate 8-bit acquisition counter is included in each stored record so missing samples can be detected in a compact data stream.

## 3. Signed 24-Bit Conversion

Each channel is transmitted most-significant byte first. The reference conversion is:

```text
value = (byte0 << 16) | (byte1 << 8) | byte2
if value has bit 23 set:
    value = value | 0xFF000000
```

The result is stored in a signed 32-bit integer. No floating-point conversion is performed in the acquisition path. Scaling to volts or millivolts belongs in the analysis layer, where the selected reference and gain can be applied explicitly.

## 4. Diagnostic Checks

Each valid frame carries its raw channels plus diagnostic metadata:

- Positive and negative lead-off masks.
- Per-channel saturation mask.
- Converter status word.
- Configuration/diagnostic flags.
- Common-mode step estimate.
- Differential step estimate.

The raw values are retained even when a diagnostic flag is set. Analysis software should mark those samples as suspect rather than silently deleting them.

The following conditions should be reported separately:

```text
LEAD_OFF       Electrode contact or cable condition may be poor.
DC_SATURATION  One or more channels are near the ADC limit.
CABLE_NOISE    Common-mode movement is unusually large.
RLD_UNSTABLE   Common-mode and differential movement indicate possible loop instability.
```

These flags describe signal quality. They are not a medical interpretation.

## 5. Buffering And Scheduling

The acquisition task owns sensor reads and places complete ECG samples into a queue without blocking on display, networking, or SD-card operations.

The output/logging task drains the queue and performs the slower work:

- display processing;
- USB and WiFi streaming;
- binary SD record construction;
- buffered SD writes.

If a queue is full, the implementation records the loss event and preserves the newest sample. The sequence counters are the authoritative way to detect the resulting gap.

## 6. Binary SD Record

The binary file begins with a 64-byte header. Each following sample record is exactly 64 bytes and is little-endian:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | elapsed time in milliseconds |
| 4 | 4 | ECG timestamp in microseconds |
| 8 | 4 | ECG sequence number |
| 12 | 4 | ECG status word |
| 16 | 4 | channel 1 raw signed value |
| 20 | 4 | channel 2 raw signed value |
| 24 | 4 | channel 3 raw signed value |
| 28 | 4 | microphone timestamp |
| 32 | 4 | accelerometer timestamp |
| 36 | 2 | microphone trace, signed Q15 |
| 38 | 2 | microphone level, signed Q15 |
| 40 | 2 | accelerometer X in mg |
| 42 | 2 | accelerometer Y in mg |
| 44 | 2 | accelerometer Z in mg |
| 46 | 2 | accelerometer raw X |
| 48 | 2 | accelerometer raw Y |
| 50 | 2 | accelerometer raw Z |
| 52 | 2 | ECG diagnostic flags |
| 54 | 1 | compact ECG acquisition sequence |
| 55 | 1 | positive lead-off mask |
| 56 | 1 | negative lead-off mask |
| 57 | 1 | ECG saturation mask |
| 58 | 1 | microphone acquisition sequence |
| 59 | 1 | accelerometer acquisition sequence |
| 60 | 1 | accelerometer diagnostic flags |
| 61 | 3 | reserved |

The record format intentionally stores raw ECG values. Plotting and filtering must not be confused with acquisition integrity.

## 7. Minimum Verification Tests

Before interpreting a body recording, run these tests in order:

1. **Digital continuity:** verify record size, sequence increments, and timestamp spacing.
2. **Zero/input short test:** confirm channels do not sit at an ADC limit with a quiet input condition.
3. **Internal test signal:** enable the converter’s test source and verify the expected frequency and channel response.
4. **Known external signal:** apply a safe, isolated low-voltage test signal and compare measured amplitude and frequency with the expected values.
5. **Electrode test:** repeat with electrodes connected, then inspect lead-off and saturation masks.
6. **Body recording:** only after the previous tests pass, review a short body recording for repeatable QRS morphology.

The external source must be electrically isolated and its amplitude must be checked with an oscilloscope before connection. Never connect a laboratory signal generator directly to a person.

## Reference Validator

Run the standard-library validator from the repository root:

```text
python Algorithms/ECG/ecg_log_validator.py path\to\recording.bin
```

It prints a machine-readable summary and returns a non-zero exit code for an invalid header, truncated record, or sequence gap.
