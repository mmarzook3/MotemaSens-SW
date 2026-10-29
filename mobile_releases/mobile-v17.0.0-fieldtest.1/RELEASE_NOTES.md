# MotemaTech Android field-test update 1

App version:17.0.0-dev+17002. Date:29 October 2026.
Publication authorized by the owner as a field-test update with limitations.
Not an unrestricted production or clinical release.

## Update

Open the existing app's account/update screen and check for an app update.
Download the APK and accept Android's installation prompt. If Android asks,
allow installation from the browser/download app used. Do not uninstall the old
app: this update retains its package and signing certificate to preserve data.
The launcher name is MotemaTech. One app supports MotemaSens and SwallowSens.
Firmware is NOT included or changed; retain your existing device firmware.

## Changes

- Shared product recognition and product-appropriate ECG/EMG views.
- Live microphone listening accepts measured rates near nominal (such as2002Hz).
- Audio packet bursts are queued instead of dropped while a send is pending.
- Bounded audio buffering reduces underruns; output is intentionally delayed.
- Phone recording fixes cover checkpoint writes, timestamp wrap, unique folders
  and interrupted-session handling. Raw sensor recordings remain unchanged.

## Test evidence and limitations

On Honor, a60-second simultaneous listening/live-view/phone-recording run had
zero Android audio underruns. Its88-second saved/exported recording contained
362925 samples. A sequence discontinuity occurred in each stream within the
first0.5s, with no subsequent discontinuities. Startup continuity remains open.
Listening latency was about0.9s; do not use perceived playback timing for ECG-PCG
interval measurements. Acoustic quality still needs listener confirmation.

Security migration remains pending: legacy device/local authentication, firmware
TLS verification, MQTT transport and managed Android signing-key custody need
qualification. This update retains the established signer for compatibility.
SD tests, calibrated analog/timing validation and long-duration field acceptance
are incomplete. Do not treat this app as a clinically validated diagnostic tool.

## Please test

Verify sign-in, device recognition and Local/BLE/Remote control. Use headphones
at low volume for listening. Record while listening, stop, reopen, scrub and
export CSV. Report audio gaps, delays, reconnects or missing samples and upload
diagnostics with device serial, firmware/app version and approximate event time.

The normal in-app manifest advertises this explicitly authorized field test.
No firmware manifest, VPS deployment or public firmware binary changes.
