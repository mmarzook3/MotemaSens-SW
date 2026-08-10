# MotemaSens v7.0.0

This is a formal validation release for the next ECG, microphone and IMU tests.

## Update through the mobile app

1. Install the current MotemaSens mobile app (`v9`).
2. Connect the device to WiFi and open the app.
3. Open **Software Update**.
4. Select **MotemaSens v7** and start the update.
5. Keep the device powered and connected to WiFi until it restarts.
6. Confirm the device reports `v7.0.0` after restart.

Only `firmware.bin` is transferred by mobile OTA. The bootloader and partition files are not changed by this update.

## Test note

The release passed software build, parser and mobile-app checks. Physical device validation is still pending. For the requested validation recording, use a USB power bank only, with no laptop, desktop, charger or other mains-powered equipment connected during the recording. Save the original `.bin` file and the post-recording device status for review.

## USB updater

The additional `.bin` files in this folder are for the USB updater only. Use the MotemaSens updater tool when a full USB flash is required.
