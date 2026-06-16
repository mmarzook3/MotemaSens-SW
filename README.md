# MotemaSens-SW

Public flashing package for MotemaSens devices.

This repository contains only customer flashing files:

- Windows updater GUI
- Customer USB logging and SD log conversion tools
- Released ESP32 binary files
- Released Android app APK
- Release manifest and checksums

It does not contain private firmware source code, customer data, factory secrets, or development logs.

## Fast Start

1. Download this repository as a ZIP from GitHub.
2. Extract the ZIP.
3. Connect the MotemaSens device to the PC using USB.
4. Run:

```text
run_motemasens_sw_updater.bat
```

The BAT file checks Python prerequisites, installs `pyserial` and `esptool` if missing, then opens the updater GUI.

## Customer Tools

USB live logging and SD log conversion tools are included under:

```text
customer_tools
```

For direct USB logging, status viewing, USB start/stop control and SD `.bin` to CSV conversion from one GUI, run:

```text
customer_tools\usb_logger\run_motemasens_usb_logger.bat
```

For only converting an SD card binary log to CSV, run:

```text
customer_tools\bin2csv\run_bin2csv_gui.bat
```

The USB logger uses the ESP32 USB serial commands `S`, `X`, and `DEVICE_SERIAL?`. It saves live USB `LOG_HEADER`/`LOG` rows to CSV and can optionally save the full raw serial output beside the CSV.

## Android App Download

Current Android app release:

| Item | Value |
| --- | --- |
| App public version | `v4` |
| Flutter app version | `1.0.29+29` |
| Download APK | [motemasens-mobile-v4.apk](https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/mobile_releases/v4/motemasens-mobile-v4.apk) |
| Checksum | [motemasens-mobile-v4.apk.sha256](https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/mobile_releases/v4/motemasens-mobile-v4.apk.sha256) |
| Release metadata | [manifest.json app section](https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/manifest.json) |

On Android, download the APK, open it, and allow install from browser/files if Android asks. This APK is signed for direct sideload testing until Play Store signing is configured.

## Current Release

| Item | Value |
| --- | --- |
| Public version | `v3` |
| Firmware version | `dev-2026.06.15.34-battery-float` |
| Dev source commit | `eb7410947323308a55ddcf882038cf1bbb89a00d` |
| Release date | `2026-06-15` |

## What The Updater Does

The updater:

1. Reads `manifest.json` from this public repository.
2. Shows released firmware versions in a dropdown.
3. Auto-selects the likely ESP32 USB COM port.
4. Downloads the selected release files.
5. Verifies SHA256 checksums.
6. Flashes the ESP32-S3 using `esptool`.
7. Restarts the device.

## Flash Layout

| File | Address |
| --- | --- |
| `bootloader.bin` | `0x0` |
| `partitions.bin` | `0x8000` |
| `boot_app0.bin` | `0xE000` |
| `firmware.bin` | `0x10000` |

## Troubleshooting

- If no COM port appears, reconnect USB and click `Refresh ports`.
- If Python is missing, the BAT file will try to install it using `winget`.
- If flashing fails, close any Serial Monitor/PlatformIO window using the COM port.
- If the device does not boot after flashing, run the updater again and enable `Erase flash before update`.

## Release Policy

Only approved releases from `mmarzook3/MotemaSens` main branch are published here.
Private firmware source, development logs, debug builds, secrets, and factory credentials are not published to this repository. The customer mobile app source is mirrored under `mobile_app/` for release transparency.

## Mobile App Release Notes

The mobile app source is mirrored into `mobile_app/` for customer-visible release builds. Released APK files are stored under `mobile_releases/<version>/`, and the non-breaking `app` block in `manifest.json` lets the app check for updates without changing the firmware manifest fields.
