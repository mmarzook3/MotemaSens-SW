# MotemaSens-SW

Public flashing package for MotemaSens devices.

This repository contains only customer flashing files:

- Windows updater GUI
- Released ESP32 binary files
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

## Current Release

| Item | Value |
| --- | --- |
| Public version | `v2` |
| Firmware version | `dev-2026.06.15.28-lcd-sd-footer` |
| Dev source commit | `d984c32c0720108ecfa40f458554c0b9daeee36f` |
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
Development code, debug builds, secrets, and source files are not published to this repository.
