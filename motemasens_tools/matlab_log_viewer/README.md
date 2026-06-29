# MotemaSens MATLAB Log Viewer

Use this MATLAB script to review MotemaSens ECG, microphone, and movement logs.

This tool was added for:

```text
Issue #1 - ECG signal is corrupted
```

GitHub issue:

https://github.com/mmarzook3/MotemaSens-SW/issues/1

## File

```text
plottingdata_clean_ecg.m
```

## What It Opens

- MotemaSens `.bin` files copied from the SD card.
- Converted `.csv` files.

## How To Use

1. Open MATLAB.
2. Open `plottingdata_clean_ecg.m`.
3. Press `Run`.
4. Select the MotemaSens `.bin` or `.csv` log file.
5. Review the ECG quality report and plots.

## Recommended Issue #1 Review Steps

1. First open the original `.bin` log directly.
2. Check the MATLAB command window for the ECG quality report.
3. Open the `MotemaSens ECG - Quality Flags` plot.
4. Look for noisy, contact warning, or saturated sections.
5. Use the `MotemaSens ECG - Raw and Cleaned View` plot to compare the raw signal with the cleaned viewing signal.
6. Use the `MotemaSens ECG - Clean View` plot to check whether a useful ECG shape is visible after bad sections are blanked.

## What It Shows

- Raw ECG and cleaned ECG view.
- ECG quality warnings for noisy/contact/saturated sections.
- Clean ECG view with bad sections blanked.
- Microphone and movement traces when present.

The cleaned ECG view is for easier inspection. Keep the raw log file for the original recording.
