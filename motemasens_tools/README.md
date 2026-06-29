# MotemaSens Tools

This folder contains Windows tools for MotemaSens devices.

## Device Software Updater

Folder:

```text
motemasens_tools/sw_updater
```

Run:

```text
run_motemasens_sw_updater.bat
```

Use this to install a released MotemaSens device software version over USB.
Close any serial monitor, USB logger, or other program using the device COM
port before flashing.

## USB Logger

Folder:

```text
motemasens_tools/usb_logger
```

Run:

```text
run_motemasens_usb_logger.bat
```

Use this for direct USB live logging, USB control, serial status viewing, and
SD `.bin` to CSV conversion from one GUI.

## MATLAB Log Viewer

Folder:

```text
motemasens_tools/matlab_log_viewer
```

Run in MATLAB:

```text
plottingdata_clean_ecg.m
```

Use this to open MotemaSens `.bin` or `.csv` logs and review ECG quality,
cleaned ECG plots, microphone data, and movement data.

This was added for GitHub Issue #1:

```text
https://github.com/mmarzook3/MotemaSens-SW/issues/1
```

## SD BIN to CSV Converter

Folder:

```text
motemasens_tools/bin2csv
```

Run:

```text
run_bin2csv_gui.bat
```

Use this when you only need to convert an SD card `.bin` log into CSV.
