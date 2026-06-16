# MotemaSens

MotemaSens is a portable monitoring device and mobile app for recording ECG, microphone heart-sound, and motion data. This repository contains the released app, device software files, and PC tools needed to update the device and work with recorded logs.

## What You Can Do

- View the device status on the round screen.
- Control the device from the Android app.
- Record ECG, MIC, and IMU/motion data to the SD card.
- Download or convert recorded logs.
- Capture a live USB log directly to a PC.
- Update the Android app and device software.

## Quick Start

1. Charge or power the MotemaSens device.
2. Power on the device and wait for the round display to finish startup.
3. Install the Android app from the latest APK below.
4. Connect the phone to the same WiFi network as the device, or use BLE mode.
5. Use the app to start and stop logging.
6. Use the PC tools in `motemasens_tools` if you need USB logging or SD log conversion.

## Android App Download

Current Android app release:

| Item | Value |
| --- | --- |
| App public version | `v4` |
| App version | `1.0.29+29` |
| Download APK | [motemasens-mobile-v4.apk](https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/mobile_releases/v4/motemasens-mobile-v4.apk) |
| Checksum | [motemasens-mobile-v4.apk.sha256](https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/mobile_releases/v4/motemasens-mobile-v4.apk.sha256) |

On Android, download the APK, open it, and allow install from browser or file manager if Android asks.

## Device Display Guide

The round display is designed to show only the most important information.

### Top Area

| Display item | Meaning |
| --- | --- |
| Battery percentage | Estimated battery level when a battery is connected. |
| Battery icon | Battery state. If no battery is detected, the display shows a no-battery status instead of a fake percentage. |
| Green dot | WiFi status. Solid green means connected, blinking means trying to connect, red means failed. |
| Blue dot or X | BLE status. Blue dot means connected, blue X means not connected. |
| Yellow dot or X | VPS/remote status. Yellow dot means remote service connected, yellow X means not connected. |

### Device Info Line

The small text line shows:

```text
FW: software version | SL: device serial | IP: device IP address
```

Use the IP address when connecting in Local mode from the app.

### Waveform Area

The main display area shows the live MIC and ECG waveforms when the device is idle. When logging starts, the waveform display may stop or simplify so the device can focus on recording stable data.

### Sensor Status Row

The display shows a compact health row:

```text
MIC | ECG | IMU | SD
```

Common status values:

| Status | Meaning |
| --- | --- |
| `ON` | Active and working. |
| `LOG` | Logging is active. |
| `ERR` | The device detected a problem with that signal or storage. |
| `SAT` | The signal is saturated or clipped. |
| `LOFF` | ECG lead contact may be off or poor. |

If all key checks pass, the screen shows:

```text
All Systems Normal
```

If there is an error, check the app status screen or reconnect/restart the device.

### SD Card Area

The bottom of the display shows whether the SD card is available and the free/total space when the card is detected.

## Using the Mobile App

Open the MotemaSens app. The main options are:

| App option | Use it for |
| --- | --- |
| Local | Control the device over the same WiFi network. |
| Remote | Control a device through the MotemaSens remote service. |
| BLE | Connect directly by Bluetooth Low Energy. Useful for setup and fallback control. |
| Debug | Advanced setup tools protected by a code. Use only when instructed. |

### Local Mode

Use Local mode when the phone and device are on the same WiFi network.

1. Read the device IP address from the round display.
2. Open the app.
3. Tap `Local`.
4. Enter the device address, for example:

```text
http://192.168.5.29
```

5. Tap connect or refresh.
6. Use the app controls to view status, start logging, stop logging, or open the software update screen.

### BLE Mode

Use BLE when WiFi is not ready or when setting up the device.

1. Turn on Bluetooth on the phone.
2. Open the app and tap `BLE`.
3. Scan for MotemaSens devices.
4. Select the device by name and serial number.
5. Use BLE controls to check status, start/stop logging, restart the device, or configure WiFi.

### Remote Mode

Use Remote mode when the device and phone are not on the same local network.

1. Make sure the device has internet access.
2. Open the app and tap `Remote`.
3. Use the server:

```text
https://ms.nwatt.uk
```

4. Sign in with the account details provided for the device.
5. Select the device by serial number.
6. Use the remote controls to view device status or start/stop logging.

### Debug Mode

Debug mode is for setup and support. It can be used to:

- Change the device WiFi SSID and password.
- Force all LEDs off.
- Run LED tests.
- Restart the device.

Use it only when you know what you are changing.

## Logging to SD Card

SD logging is the normal way to record longer sessions.

1. Insert the SD card before starting the session.
2. Open the app and connect using Local or BLE.
3. Find the `Write to SD card` section.
4. Select one or more channels:
   - ECG
   - MIC
   - IMU
   - All
5. Tap `All` or select the required channels.
6. Confirm the display shows logging status.
7. Keep the device stable during the session.
8. Tap `Stop` before removing power or removing the SD card.

SD logs are saved as binary files for speed. Convert them to CSV before viewing them in Excel or plotting tools.

## Downloading Logs from the App

When connected in Local mode:

1. Open the `Storage` tab.
2. Tap refresh.
3. Select the log file.
4. Download it to the phone, or copy the file link.
5. Convert `.bin` files to CSV if needed.

## USB Logging on a PC

USB logging is useful for live testing, quick checks, and support captures.

### Open the USB Logger

Download this repository as a ZIP, extract it, then run:

```text
motemasens_tools\usb_logger\run_motemasens_usb_logger.bat
```

The tool opens a GUI for USB logging and status viewing.

### USB Logging Steps

1. Connect MotemaSens to the PC using a USB data cable.
2. Open the USB Logger.
3. Select the MotemaSens COM port. It usually appears like:

```text
COM7 - USB-Enhanced-SERIAL CH343
```

4. Use baud `115200` for the current release.
5. Choose an output folder and CSV filename.
6. Click `Connect`.
7. Click `Start log`.
8. Watch the row count and live preview.
9. Click `Stop log`.

The tool saves:

```text
motemasens_usb_YYYYMMDD_HHMMSS.csv
motemasens_usb_YYYYMMDD_HHMMSS.serial.txt
```

The CSV file contains the live log rows. The `.serial.txt` file contains the full USB text output and is useful for support.

## Converting SD Binary Logs to CSV

You can convert SD `.bin` files using either:

```text
motemasens_tools\usb_logger\run_motemasens_usb_logger.bat
```

or the standalone converter:

```text
motemasens_tools\bin2csv\run_bin2csv_gui.bat
```

Steps:

1. Open the converter.
2. Browse and select the `.bin` file.
3. Choose the output folder.
4. Choose the CSV filename.
5. Click `Convert`.
6. Open the CSV in Excel, LibreOffice, Python, or the MotemaSens CSV viewer.

## Updating the Device Software

Use the updater when a new MotemaSens device release is provided.

1. Download this repository as a ZIP from GitHub.
2. Extract the ZIP.
3. Connect the device to the PC using USB.
4. Run:

```text
run_motemasens_sw_updater.bat
```

5. Select the released version.
6. Select the MotemaSens COM port.
7. Click `Flash selected version`.
8. Wait until flashing is complete and the device restarts.

Do not unplug the device during flashing.

## Current Device Release

| Item | Value |
| --- | --- |
| Public version | `v3` |
| Device software version | `dev-2026.06.15.34-battery-float` |
| Release date | `2026-06-15` |

## Troubleshooting

| Problem | What to try |
| --- | --- |
| App cannot connect in Local mode | Make sure the phone and device are on the same WiFi. Check the IP on the display. |
| BLE scan does not find the device | Turn Bluetooth off/on, allow nearby-device permission, then scan again. |
| No SD card shown | Reinsert the card and restart the device. |
| ECG status shows `LOFF` | Check electrode contact and cable connection. |
| MIC signal is small | Hold the device closer and reduce clothing rub or background noise. |
| USB Logger shows no rows | Check the COM port and baud rate. Use `115200` for current release. |
| Flashing fails | Close any serial monitor or USB logger using the COM port, reconnect USB, and try again. |
| Device does not start after update | Run the updater again. If needed, enable erase flash before update. |

## Privacy

MotemaSens logs may contain personal physiological and motion data. Store, share, and delete logs carefully.

## Repository Contents

| Folder/File | Purpose |
| --- | --- |
| `mobile_releases` | Released Android APK files. |
| `releases` | Released device software files. |
| `motemasens_tools` | USB logger and log conversion tools. |
| `run_motemasens_sw_updater.bat` | Windows device software updater launcher. |
| `manifest.json` | Release information used by the updater and app. |
