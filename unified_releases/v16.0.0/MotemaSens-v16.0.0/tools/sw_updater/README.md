# MotemaSens software updater

Use this Windows tool to install an official MotemaSens firmware release over USB.

## Before starting

- Keep the MotemaSens device connected directly to the computer by USB.
- Close serial monitors and any other program using the device COM port.
- Keep the computer connected to the internet while the release list downloads.

## Install an update

1. Run `run_motemasens_sw_updater.bat`.
2. Wait while the launcher checks and installs its Python requirements.
3. Select the MotemaSens USB serial port. The updater places recognised MotemaSens USB ports first.
4. Select the required official release.
5. Select **Flash selected version**.
6. Keep the cable connected until the updater confirms that flashing and verification completed.
7. Wait for the device to restart and confirm the new version on its display or in the mobile app.

The updater installs the application firmware only. It does not change the device serial number or factory registration.

## If the COM port cannot be opened

1. Close all serial monitors, terminal programs and other updater windows.
2. Disconnect and reconnect the USB cable.
3. Select **Refresh ports** and choose the MotemaSens port again.
4. Retry the update.

Do not disconnect USB while a flash operation is in progress.
