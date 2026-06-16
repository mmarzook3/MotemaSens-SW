# MotemaSens USB Logger

This is the customer/support PC tool for MotemaSens USB serial logging.

## What it does

- Finds ESP32 USB serial ports and puts likely MotemaSens ports first.
- Connects to the ESP32 USB serial port.
- Starts USB live logging by sending `S`.
- Stops USB live logging by sending `X`.
- Queries device serial identity with `DEVICE_SERIAL?`.
- Saves `LOG_HEADER` and `LOG` rows to CSV.
- Optionally saves the full raw serial output beside the CSV.
- Shows live status:
  - connection state
  - capture state
  - firmware version
  - device serial/device ID
  - IP address when printed by firmware
  - row count
  - row rate
  - elapsed time
  - beat count and BPM
  - ECG status
- Shows a small live preview of MIC and ECG traces.
- Converts SD card `.bin` files to CSV using the same converter as `tools/customer_tools/bin2csv`.

## How to run on Windows

Double-click:

```text
run_motemasens_usb_logger.bat
```

The BAT file checks for Python, installs `pyserial` if needed, then opens the GUI.

## USB logging workflow

1. Connect the MotemaSens device to the PC with a USB data cable.
2. Open `run_motemasens_usb_logger.bat`.
3. Select the ESP32 COM port. It normally appears as something like:

```text
COM7 - USB-Enhanced-SERIAL CH343
```

4. Use baud `115200` for current customer firmware.
5. Use baud `921600` only for older fast dev firmware that was built for that baud.
6. Choose an output folder and CSV filename.
7. Click `Connect`.
8. Click `Start USB log`.
9. Wait for CSV rows and the live preview.
10. Click `Stop USB log`.

The firmware also stops automatically after its configured USB live-log duration.

## Output files

The GUI writes:

```text
motemasens_usb_YYYYMMDD_HHMMSS.csv
motemasens_usb_YYYYMMDD_HHMMSS.serial.txt
```

The CSV contains the MotemaSens USB live rows and can be opened in Excel,
LibreOffice, Python, or the MotemaSens CSV HTML viewer.

The `.serial.txt` file contains all serial messages, including boot messages,
status lines, `BEAT` lines, and any firmware debug text.

## BIN to CSV converter tab

Use the `BIN to CSV` tab when the log came from the SD card instead of USB.

1. Pick the MotemaSens SD `.bin` file.
2. Pick the output folder.
3. Choose a CSV filename.
4. Click `Convert BIN to CSV`.

The converter expects MotemaSens binary logs with the `MSLOGB1` header.

## Troubleshooting

| Problem | First check |
| --- | --- |
| No COM port shown | Use a USB data cable, reconnect the device, then click `Refresh`. |
| Flashing tool cannot use the port | Close this USB Logger first. Only one program can own the COM port. |
| No rows after Start | Check baud rate. Current customer firmware uses `115200`. |
| Strange characters in serial view | Wrong baud rate selected. Try `115200`, then `921600`. |
| CSV is empty | Confirm `LIVE_TEST_START` appears after clicking Start. |
| Device does not stop | Click Stop again or disconnect USB after saving the current capture. |

## Firmware command reference

The current firmware supports these USB serial commands:

```text
S
X
DEVICE_SERIAL?
```

- `S` starts the firmware USB live logger.
- `X` stops the firmware USB live logger.
- `DEVICE_SERIAL?` prints device serial, device ID, and BLE name.
