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
