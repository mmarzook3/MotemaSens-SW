# ECG Recording Review: 13 July 2026

This review covers the three binary files supplied with the updated firmware test results. The original files remain in the private project email folder and are not copied into the public release repository.

## Files Reviewed

| File | Records | Duration | Observed ECG rate | Sequence gaps |
| --- | ---: | ---: | ---: | ---: |
| `TestA.bin` | 25,245 | 50.568 s | 510.20 Hz | 0 |
| `TestB.bin` | 19,984 | 40.044 s | 509.94 Hz | 0 |
| `TestC.bin` | 25,618 | 51.326 s | 510.73 Hz | 0 |

All three files have the expected 64-byte header and 64-byte record size. The recorded firmware string is `dev-2026.06.15.34-battery-float` and the channel mask is `7`.

## What The Data Proves

- The files are not being damaged by the binary-to-CSV conversion step.
- The record boundaries are consistent.
- ECG sequence numbers increment by one for every stored record in all three files.
- There is no evidence of dropped ECG records in these files.
- The measured timestamp interval is close to the 500 SPS target, but the observed rate is approximately 510 Hz in these recordings and should be checked against the intended converter data-rate configuration.

## ECG Quality Findings

The raw ECG channels reach or approach the signed 24-bit converter limits in all three recordings. Examples include channel values at `-8388608` and positive values above `8,300,000`. Saturation masks are present in 97, 81, and 102 records respectively.

Lead-off masks are also intermittent:

| File | Positive lead-off records | Negative lead-off records |
| --- | ---: | ---: |
| `TestA.bin` | 1,020 | 1,264 |
| `TestB.bin` | 1,615 | 1,001 |
| `TestC.bin` | 751 | 1,752 |

The diagnostic flag values are present throughout the files because configuration/status flags are carried with each record. They should be decoded by bit rather than treating every non-zero value as a failure.

## Engineering Conclusion

The recordings show a healthy storage and sequence path, but they do not yet show a clean ECG acquisition path. The main issue is present in the raw ECG values before plotting. The evidence points to one or more of:

- input or electrode contact conditions;
- converter configuration or data-rate verification;
- frame status/channel interpretation;
- saturation or common-mode conditions during acquisition;
- signal-quality handling after the frame is read.

The absence of sequence gaps makes a simple SD write-loss explanation unlikely for these files. It does not by itself prove that every SPI frame contains the intended channel alignment, so a known test-signal recording is the next decisive test.

## Recommended Evidence To Collect

1. Record the converter register readback at startup.
2. Record a short internal test-signal file and verify its frequency and channel pattern.
3. Record a safe, isolated known-amplitude external test signal after checking it with an oscilloscope.
4. Compare the expected signal with the raw channel values before filtering.
5. Report sequence gaps, timestamp interval, status word, lead-off masks, and saturation masks together.

This review is for engineering debugging. It is not a medical performance assessment.
