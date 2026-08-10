# MotemaSens BIN to CSV Converter

This folder is the customer-facing converter for MotemaSens SD card logs.

## What it does

- Opens a MotemaSens `.bin` file from the SD card.
- Converts it to a CSV file.
- Keeps the data format compatible with the MotemaSens CSV viewer.
- Lets the customer choose the output folder and filename.
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

The converter supports v1, v2 and v3 logs. V2 CSV output includes `mic_raw_0`
to `mic_raw_3`: four successive microphone samples stored with each 500 Hz ECG
record, giving a 2,000 Hz microphone stream without repeated display values.

V3 logs from device software v7 add microphone validity and missing-block reason
fields, IMU validity/age/sequence fields, and a clean-stop session trailer. The
converter verifies the v3 payload CRC32 and reports the session state after
conversion. Missing microphone blocks remain marked in the CSV; they are not
replaced with silent samples or removed from the timeline.

## Output

The output CSV contains the decoded ECG, MIC and IMU values so it can be opened in:

- Excel
- LibreOffice
- the MotemaSens HTML CSV viewer

## Notes

- The tool is meant for customer use.
- It does not flash firmware.
- It does not need the full private firmware repo.
