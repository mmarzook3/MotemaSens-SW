# Binary Log Format v4

Format v4 replaces the fixed ECG-rate combined record with independently timestamped acquisition chunks. It exists to preserve the real 500 Hz ECG, 2 kHz microphone and approximately 125 Hz IMU streams without copying a latest value into another stream's row.

## Compatibility

- v1, v2 and v3 remain readable by the Python converter, Flutter app and MATLAB reader.
- v4 uses the existing 64-byte `MSLOGB1` header with `formatVersion = 4` and `recordSize = 0`.
- A reader must select its parser from `formatVersion`; it must never infer v4 data as a fixed-size row format.

## Timing contract

All chunk timestamps are `sessionUs`, an unsigned microsecond offset from the recording-session anchor established by Core 0.

- ECG: timestamp captured at the data-ready acquisition event.
- MIC: timestamp derived from the first sample's continuous source sequence at 2 kHz. A microphone chunk contains up to eight sequential raw signed 16-bit samples at 500 microsecond spacing.
- IMU: timestamp captured after the IMU sample is acquired.
- GAP: timestamp identifies the nominal time of the first expected missing sample. Readers expand the range at the stream's defined sample interval and retain the GAP event itself; they never invent sensor values.

The streams do not claim a common hardware sampling edge. They share a defined session epoch, which permits offline alignment without claiming sub-sample synchrony that the prototype cannot prove.

## Chunk framing

Every payload starts with this packed 16-byte header, little-endian.

| Offset | Field | Type | Meaning |
| ---: | --- | --- | --- |
| 0 | `type` | `uint8` | `1` ECG, `2` MIC, `3` IMU, `4` GAP, `5` session diagnostics. |
| 1 | `flags` | `uint8` | Bit 0 is acquisition-valid. IMU also uses bits 1–3 for healthy X/Y/Z axes. |
| 2 | `payloadSize` | `uint16` | Number of payload bytes immediately following the header. |
| 4 | `sequence` | `uint32` | Source acquisition sequence for that stream. |
| 8 | `sessionUs` | `uint64` | Microseconds since the session anchor. |

All raw acquisition values are stored unchanged. The display waveform, scaling, smoothing and notch processing never modify values written to SD.

## Payloads

| Chunk | Payload size | Contents |
| --- | ---: | --- |
| ECG | 28 bytes | Status word, four signed 24-bit-in-`int32` raw channels, diagnostic flags, frame-read delay, lead-off positive/negative masks and saturation mask. |
| MIC | 20 bytes | `sampleCount` followed by up to eight sequential raw signed 16-bit microphone samples. |
| IMU | 16 bytes | X/Y/Z milligravity, raw X/Y/Z, and IMU diagnostic flags. |
| GAP | 20 bytes | Stream identifier, reason, explicit number of missing samples, expected sequence and next observed sequence. |
| Session diagnostics | 144 bytes | Versioned session result, Core 1/SD timing, queue pressure and drops, start/stop acknowledgement, discarded pre-session packets, SD failures, and first/last sequence and timestamp for each stream. |

`GAP` chunks are the only representation of known loss. Missing data must not be represented by repeated values, zero-filled microphone values or invented timestamps.

### Session diagnostics schema 1

The type-5 payload is an additive v4 extension. Older v4 readers may skip the
unknown chunk by using `payloadSize`; v12 readers decode it. Its packed
little-endian layout is:

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion`, `payloadSize` | `uint16`, `uint16` | Diagnostics schema `1` and payload length `144`. |
| `quality` | `uint8` | `0` unverified, `1` complete, `2` minor loss, `3` failed. |
| Core 1/SD maxima | 3 x `uint32` | Maximum Core 1 loop interval, Core 1 busy duration and buffered SD write duration in microseconds. |
| Queue high-water | 3 x `uint16` | Maximum queued ECG packets, microphone frames and IMU packets. |
| Operation/ack timing | 3 x `uint32` | Rejected storage operations, start acknowledgement and stop acknowledgement. |
| Pre-session discard | 3 x `uint32` | ECG, microphone and IMU transport packets removed before arming. These are outside the recording and are not session loss. |
| Queue drops | 3 x `uint32` | ECG, microphone and IMU queue drops during the session. |
| `sdWriteFailures` | `uint32` | Failed SD payload/trailer writes during the session. |
| Per-stream bounds | 3 x (`uint32`, `uint32`, `uint64`, `uint64`) | First/last source sequence and first/last session timestamp for ECG, microphone and IMU. |

The session diagnostics chunk is written immediately before the clean-stop
trailer and is included in the trailer chunk count and CRC. It does not alter
or filter any acquisition sample.

### Session quality

- `COMPLETE`: trailer/CRC verification passes, stream accounting reconciles,
  and no loss or warning condition was observed.
- `MINOR_LOSS`: structure verifies, but at least one explicit gap, invalid ECG
  frame, overrun, ECG saturation/lead-off/configuration warning, queue drop, or
  IMU acquisition warning exists.
- `FAILED`: structure verification fails, microphone accounting does not
  reconcile, an SD write fails, or explicit loss reaches 1% in any enabled
  stream.
- `UNVERIFIED`: recording has not reached a verified stop.

## Clean-stop trailer

A normal stop first closes the acquisition generation on Core 0, drains every packet already captured for that generation on Core 1, then appends one 152-byte `MSENDV4` trailer. It contains the payload CRC32, chunk count, elapsed session time and session totals for ECG invalid/late/overrun events, microphone acquired/persisted/explicit-gap/queue-drop counts, IMU updates/failures and SD dropped chunks.

The firmware closes the file and then re-opens it on Core 1 to compare the stored trailer, recompute the payload CRC32, and validate every chunk type, payload size and final chunk count. Only this readback result is reported as a verified recording through local Wi-Fi status, cloud status and the mobile app. A failed SD write or failed reread is reported as a failed stop; it must not be described as a successful recording.

`ecgLateFrames` is retained as an acquisition-latency diagnostic. It does not by
itself mean that a conversion was missed: missed data are represented by an ECG
overrun, invalid frame, explicit gap, or failed stream accounting. Python,
Flutter and MATLAB therefore report a late-only, otherwise verified recording
as `COMPLETE` while continuing to expose the late-frame count for engineering
review.

Core 1 maximum stall/busy time is also retained for engineering review. A
latency observation does not by itself claim missing data or change the quality
result; explicit gaps, invalid frames, overruns, queue/SD drops and stream
accounting are the authoritative loss indicators.

The primary microphone accounting invariant is:

```text
microphone samples acquired = microphone samples persisted + explicit microphone gaps
```

If no clean-stop trailer is present, a reader may recover complete chunks up to the final complete chunk but must mark the session incomplete. The Python converter verifies the payload CRC32; the MATLAB reader reports trailer presence and leaves CRC verification to the Python converter.

A complete file containing an explicit GAP is valid for waveform review, but it is not suitable for precise timing calculations that involve the affected stream. This applies to ECG, microphone and IMU GAPs. The Python converter reports these conditions and the release gate rejects a candidate that contains any GAP.

## Tool support

- Python: `tools/bin2csv/binary_log.py`
- MATLAB: `tools/matlab_log_viewer/read_motemasens_log.m`
- Mobile app: the built-in SD-log converter

v4 CSV output is event-based. Microphone blocks are expanded to one row per
2 kHz sample. A GAP remains visible as a `GAP` event and is followed by
timestamped `<stream>_MISSING` rows containing no invented sensor values.
Invalid ECG and IMU acquisition values are emitted as `NaN` while their status
and diagnostics remain available. Raw ECG columns are named `ecg_ch1_raw`
through `ecg_ch4_raw`; derived `lead_iii_derived` is `Lead II - Lead I`, and raw
channel 3 is never labelled as Lead III.
