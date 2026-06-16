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

## Output

The output CSV contains the decoded ECG, MIC and IMU values so it can be opened in:

- Excel
- LibreOffice
- the MotemaSens HTML CSV viewer

## Notes

- The tool is meant for customer use.
- It does not flash firmware.
- It does not need the full private firmware repo.
