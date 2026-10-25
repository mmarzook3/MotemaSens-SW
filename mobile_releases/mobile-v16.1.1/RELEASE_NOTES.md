# MotemaSens Android 16.1.1 - Support Diagnostics

Install the APK over the existing app, sign in, open your saved device and choose
Support details > Send diagnostics. Confirm consent and share the returned
report ID with support. This action requires internet access and account access
to the device. Guest users must sign in first.

The report includes versions, connection timing, reset/recovery codes, memory,
sample-rate/drop counters and preview timing/backpressure counters available
from the connected firmware. Local IP and BLE read a status snapshot. Remote
uses the last status received by the VPS and is labelled accordingly. If a
device cannot be reached, explicitly marked cached evidence can be sent.

Passwords, access tokens, WiFi names, NVS data and raw ECG/PCG/IMU recordings are
excluded. The VPS also filters report fields, restricts access, limits upload
rate and retains no more than 100 reports per device. Failed uploads can be
retried while the support screen remains open without creating duplicates.

Firmware remains v16.1.0; no firmware flash is required for this app update.
Older firmware may expose fewer diagnostic counters. Raw signal processing,
recordings and acquisition are unchanged.

Validation: 167 Flutter tests, Flutter static analysis and 17 backend tests
passed. The diagnostics backend is tested with authenticated synthetic reports
on the VPS before publication. Physical BLE/device collection has not been
validated for this patch. Report snapshots are not continuous trace captures.
