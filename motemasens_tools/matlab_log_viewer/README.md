# MotemaSens MATLAB Log Viewer

Use this MATLAB script to review MotemaSens ECG, microphone, and movement logs.

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

## What It Shows

- Raw ECG and cleaned ECG view.
- ECG quality warnings for noisy/contact/saturated sections.
- Clean ECG view with bad sections blanked.
- Microphone and movement traces when present.

The cleaned ECG view is for easier inspection. Keep the raw log file for the original recording.
