# MotemaSens Mobile

Flutter mobile controller for the MotemaSens ESP32-S3 hardware.

## Production App Flow

The app opens to four connection choices:

- `Local`: control a nearby ESP32 by IP address on the same WiFi.
- `Remote`: connect to the MotemaSens VPS endpoint at `https://ms.nwatt.uk`.
- `BLE`: nearby BLE control for normal recording controls.
- `Debug`: locked support tools. This screen requires developer code `12345`.

There is no demo/offline device mode in the production UI. If the device is not reachable, the app shows a connection error instead of fake data.

## Debug Access

The Debug screen is for bring-up and device support only.

After entering code `12345`, the app can:

- Scan for the MotemaSens BLE device.
- Read compact BLE status.
- Send WiFi SSID/password to the ESP32 over BLE.
- Force all LEDs off, including during logging.
- Clear the LED override and return the device to normal heartbeat LED mode.
- Run LED self-test.

The LED override is persisted in ESP32 preferences. If enabled, it wins over heartbeat, manual LED test, self-test and logging indicators until cleared from Debug or by firmware command.

## Firmware Interfaces

Local HTTP:

```text
GET  /api/status
POST /api/recording
POST /api/led-off-override
```

BLE service:

```text
service:       9f6d0001-6f2b-4e45-9f2f-6b4f4d53454e
status:        9f6d0002-6f2b-4e45-9f2f-6b4f4d53454e
command:       9f6d0003-6f2b-4e45-9f2f-6b4f4d53454e
wifi provision:9f6d0004-6f2b-4e45-9f2f-6b4f4d53454e
```

BLE commands used by the app:

```json
{"command":"set_leds_off_override","enabled":true}
{"command":"configure_wifi","ssid":"...","password":"..."}
{"command":"set_recording_mode","mode":"all"}
```

## Build And Test

```powershell
cd mobile
flutter pub get
flutter analyze
flutter build apk --debug
```

Install to the connected phone:

```powershell
adb -s RFCY508DWBP install -r build\app\outputs\flutter-apk\app-debug.apk
```

Install to the emulator:

```powershell
adb -s emulator-5554 install -r build\app\outputs\flutter-apk\app-debug.apk
```

The debug APK is for bench testing. A user/Play Store release still needs a proper Android release keystore and `flutter build apk --release` or app bundle signing setup.

## Changelog

### 1.0.29+29

- Published as MotemaSens Mobile `v4` so installed v3 apps can test the app update path.

### 1.0.28+28

- Local mode now shows the WiFi network name currently used by the phone, where Android permissions allow it.
- Debug access code changed to `12345`.

### 1.0.27+27

- Added a non-blocking app update check on the startup connection screen.
- The app reads the public MotemaSens-SW manifest `app` block and shows installed app version, update available, up-to-date, failed, deferred and ignored states.
- Android update action tries Play in-app update first when supported, then falls back to opening the APK URL from the manifest. iOS opens the App Store URL.
- Firmware OTA remains separate in the existing Software Update screen.
