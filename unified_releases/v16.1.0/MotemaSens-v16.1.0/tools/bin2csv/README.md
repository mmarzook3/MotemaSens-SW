# MotemaSens BIN to CSV Converter

This folder contains the user-facing converter for MotemaSens SD card logs.

## What it does

- Opens a legacy MotemaSens `.bin` file or an FI-002 recording-session folder
  containing `session.msidx` and verified `SEG_*.bin` files.
- Converts it to a CSV file.
- Streams multi-segment sessions into one continuous timestamped CSV without
  joining the binary files or loading the complete recording into memory.
- Lets the user choose the output folder and filename.
- Can overwrite an existing CSV when needed.

## How to run

1. Install Python 3 on the PC.
2. Double-click:

```text
run_bin2csv_gui.bat
```

or run:

```text
python bin2csv_gui.py
```

## What the converter expects

The file must be a MotemaSens SD binary log written by the firmware.
It starts with the `MSLOGB1` header and uses fixed-size records.

The converter supports v1, v2, v3 and v4 binary logs. V2 CSV output includes
`mic_raw_0` to `mic_raw_3`: four successive microphone samples stored with each
500 Hz ECG record, giving a 2,000 Hz microphone stream without repeated display
values. V3 adds microphone validity and missing-block reason fields, IMU timing
metadata, and a clean-stop/CRC status shown by the converter. Its clean-stop
summary also reports the total detected microphone source-gap samples for the
recording.

Updated v3 files also contain a clean-stop ECG session summary: received,
invalid, overrun, saturation, lead-off, cable-noise and RLD-unstable frame
counts, together with the recording-start configuration/readback state. The raw
ECG values in the converted CSV are not display-filtered.

V4 stores ECG, microphone and IMU data as independent timestamped chunks.
The CSV keeps explicit gap events and missing-sample rows visible instead of
inventing, repeating or interpolating sensor values. A clean-stop trailer and
CRC32 protect completed recordings, and session diagnostics remain available
for quality review.

For a multi-day recording, click **Session** and select the `S_*` folder copied
from the SD card. The converter checks the append-only session journal, every
segment state, file size, v4 trailer and payload CRC before conversion. A
missing, incomplete or corrupt segment is reported explicitly; it is never
silently skipped from a supposedly complete export.

## Output

The output CSV contains the decoded ECG, MIC and IMU values so it can be opened in:

- Excel
- LibreOffice
- the MotemaSens HTML CSV viewer

## Notes

- The tool is intended for MotemaSens users.
- It does not flash firmware.
- It does not need the full private firmware repo.
