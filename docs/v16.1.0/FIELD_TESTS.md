# v16.1.0 field acceptance

Record app/firmware version, device serial, power source, connection mode,
duration and exact steps for every result. Share de-identified original logs
and screenshots in https://github.com/mmarzook3/MotemaSens-SW/issues.

## #5 Live signals and analysis

1. Install the app before firmware. Confirm both report 16.1.0.
2. Use Local IP Signals, start live view, and confirm ECG/PCG/IMU are adjacent.
3. Select I, II and III. Compare a saved SD recording at identical calibrated
   scale; confirm III=II-I with synchronized samples. Lead selection clears the
   displayed history to avoid mixing channels.
4. Record 30 seconds with ECG and microphone, then repeat microphone-only.
   After at least four seconds of valid microphone history analysis should
   progress to a result or a specific low-quality/motion explanation.
   R-linked intervals must be unavailable in microphone-only mode.
5. Use headphones, start at low Android volume, turn Listen on/off. Verify
   responsiveness, no accumulating audio delay, and that leaving/backgrounding
   the app mutes audio. Audio latency is not validated for timing measurement.
6. Verify phone recording and SD recording remain complete while listening.
7. Briefly interrupt Wi-Fi and reconnect; report freezes, gaps or stale sound.
8. Stop recordings. Try Sleep device through Local, BLE and Remote separately.
   Confirm it refuses while logging/OTA is active, disconnects after acceptance,
   and wakes via physical RESET. USB removal alone does not remove battery power.

## #1 ECG and #4 contact

Use the approved electrode procedure and battery-only power. Compare 60-second
still recordings with held/unheld microphone contact and repeatable placement.
Record movement/talking periods separately. Retain raw recordings and validity,
saturation and timing diagnostics. Do not infer that filtering fixed contact.
Report whether silicone tears/flexure or electrode lift remains. These require
mechanical assessment and remain open after software publication.

## #2 SD and restart

Make two short recordings; verify readable names and newest-first order.
Rename one, reconnect, and confirm the SD directory/file name persisted.
Download/convert it, then delete only this disposable test recording and verify
it remains absent after reconnecting. Confirm the saved Local IP is reused.
For resets capture Device health boot count, reset reason, previous stage and
recovery count. Local GET /api/system/diagnostics supplies additional counters.
Do not post a complete NVS dump or Wi-Fi passwords in public issues.

## #3 thermal validation

On the bench, measure enclosure/contact surface temperature and ambient
temperature independently at startup, 5, 15, 30 and 60 minutes. Compare battery
idle, SD logging, Local live view and USB charging modes. Record current where
available. The displayed IMU temperature is an internal measurement only.
Stop if the device becomes unexpectedly hot; investigate charger, battery,
regulator and processor contributions before further skin-contact testing.
Existing display/radio power management is retained; no unmeasured temperature
threshold is represented as a validated skin-safety limit.

## Results

Comment PASS/FAIL for each step with supporting evidence. Keep #1, #3, #4 and
#5 open until relevant field criteria pass. An analysis output or synthetic
fixture passing is not clinical validation of S1/S2 or pathology detection.
