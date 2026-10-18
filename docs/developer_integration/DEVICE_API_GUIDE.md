# MotemaSens developer integration API

Version: firmware v16.0.0; Android reference client 16.0.1.
Source inspected: `8fed98a27f758c5d21d7a253bd5c6919d8e0be38` (2026-10-18).
This is a source-verified contract, not a claim of new physical-device testing.
No device credentials, patient recordings or private keys are included.

## 1. Choose a connection

| Transport | Purpose | Limits |
|---|---|---|
| Bluetooth Low Energy (BLE GATT) | Discover device, configure WiFi, control recording/settings, receive status | No full-rate ECG/PCG/IMU binary stream or SD file-download characteristic |
| Local WiFi HTTP, port 80 | Full status/control, live binary stream, SD downloads, local OTA | Computer and device must be mutually reachable on the LAN; normal deployment joins an existing WiFi network |
| Remote HTTPS | Account-owned device control, status, synchronized cloud recordings, OTA | Requires account membership and device cloud provisioning; not a transparent LAN proxy |
| USB serial, 921600 baud | Engineering logging/diagnostics and provisioning | CH343 is a serial interface, not USB mass storage; COM number varies |

For a Windows or MATLAB acquisition application, use BLE to obtain the IP,
then Local WiFi for live plotting and file transfer. Use original SD files for
full-fidelity offline analysis. The live stream is not the SD file format.
WiFi AP mode, WiFi Direct and Bluetooth Classic SPP are not documented interfaces
of this build. Do not assume those transports exist.

## 2. Identity and client rules

- Example identity: `deviceId=ms-0002`, serial `2`, advertised name
  `MotemaSens-ms-0002`. Discover rather than hard-code a BLE address or IP.
- Local base URL: `http://<device-ip>`; cloud base: `https://ms.nwatt.uk`.
- JSON requests: UTF-8, `Content-Type: application/json`, explicit Content-Length.
  URL-encode query values. Use server-returned session IDs and filenames.
- Read `/api/hello` first, then `/api/status`. Check identity and version before
  modifying state. `/api/hello` is a compact handshake, not the complete status.
- A 2xx response is not sufficient: parse JSON and reject `ok:false` or
  `busy:true`. Some historical routes report errors with HTTP 200.
- Check `message`/`code`, HTTP 400/409/423 and the resulting device status.
  A command acknowledgement may precede actual recording or reboot completion.
- Give each mutation a unique `requestId`, and reuse it only for retries of that
  same operation. Local/firmware deduplication uses a bounded in-memory cache
  (16 entries); it is not durable exactly-once execution across reboot.
- Serialize writes and file transfers. One device has limited CPU/socket/SD
  resources. Prefer one live client and one active download at a time.
- Stop recording before changing rates, provisioning WiFi, manipulating SD
  files, calibrating, sleeping or updating firmware. Poll completion/health.
- Local HTTP is plaintext and does not use the cloud Bearer-token contract.
  BLE characteristics do not establish a secure authenticated application
  protocol by themselves. Use trusted networks and controlled device access.
  Do not expose these LAN endpoints through public port forwarding.

## 3. BLE GATT

Service: `9f6d0001-6f2b-4e45-9f2f-6b4f4d53454e`.

| Characteristic | UUID | Properties | Encoding |
|---|---|---|---|
| Status | `9f6d0002-6f2b-4e45-9f2f-6b4f4d53454e` | Read, Notify | Compact UTF-8 JSON |
| Commands/response | `9f6d0003-6f2b-4e45-9f2f-6b4f4d53454e` | Read, Write, Notify | Complete UTF-8 JSON command / response |
| WiFi provisioning | `9f6d0004-6f2b-4e45-9f2f-6b4f4d53454e` | Read, Write, Notify | Complete UTF-8 JSON provisioning request / progress |

Scan for service/name, connect, discover characteristics, subscribe to status
and command responses, and read initial status. Use GATT write-with-response.
Do not split JSON into arbitrary writes: firmware does not define an application
fragment-reassembly protocol. Long writes and notification size depend on the
negotiated MTU and host stack. If a notification is incomplete JSON, read the
characteristic's complete value rather than treating a partial message as data.
Status is kept compact for common 512-byte read limits; fields can be omitted.

Common status aliases: `sn` serial, `id` device ID, `v` firmware, `cv` capability
version, `sv` settings revision, `wc` WiFi connected, `ip` IP, `sr` SD ready,
`sl` SD logging, `rm` recording mode, `ao` always-on, `ws` stored SSID,
`cc` cloud connected, `cr` cloud configured, `ps` provisioning stage,
`rr` reset reason code, `ds` previous execution stage, `rc` recovery count.
Use optional-field parsing. Prefer Local `/api/status` for verbose diagnostics.

### Command characteristic requests

Every row is a JSON object with `command` plus the listed fields. Add requestId.

| command | Fields / effect |
|---|---|
| `set_recording_mode` | `mode`: `idle`, `ecg`, `microphone`, `imu`, `all` |
| `set_recording_channels` | Boolean `ecg`, `mic`, `imu`; all false stops |
| `stop_recording` | Stop device recording |
| `start_usb_log`, `stop_usb_log` | Start/stop engineering USB logging |
| `set_sample_rates` | Integer `ecg`, `mic`, `imu`; persists and restarts |
| `restore_sample_rates` | Restore 500/2000/125 defaults and restart |
| `get_settings` | Return settings snapshot |
| `apply_settings` | Flat settings fields described below |
| `set_power_bank_mode` | Boolean `enabled`; persist always-on setting |
| `set_usb_msc` | Boolean `enabled`; only supported hardware/builds |
| `set_led` | `led`: `green`, `blue`, `all`; Boolean `enabled` |
| `set_leds_off_override` | Boolean `enabled` |
| `led_heartbeat` | Restore automatic LED heartbeat |
| `self_test` | Start device self-test; not a clinical signal-quality test |
| `reconnect_wifi` | Reconnect using stored WiFi settings |
| `restart_device` | Scheduled reboot |
| `sleep_device` | Guarded deep sleep; wake with RESET or complete power cycle |
| `get_wifi_credentials` | Sensitive: returns stored SSID/password |
| `create_claim_proof` | `challengeId`, `nonce`; returns device-generated claim proof |

Examples:

```json
{"command":"set_recording_channels","ecg":true,"mic":true,"imu":true,"requestId":"desktop-001"}
```

```json
{"command":"stop_recording","requestId":"desktop-002"}
```

Check response `ok` and `message`, then read status. Specialized commands can
return their own snapshot/proof object rather than a generic acknowledgement.

### WiFi provisioning characteristic

```json
{"command":"configure_wifi","requestId":"setup-001","ssid":"LAB_WIFI","password":"<provided securely>"}
```

`requestId` and nonempty `ssid` are required; password may be empty for an open
network. Progress includes credential save and WiFi connection stages; wait for
the reported connected IP/local readiness. Save acknowledgement alone is not
proof of successful association. A concurrent provisioning operation can fail
with `PROVISIONING_BUSY`. Never log passwords or include them in shared traces.

## 4. Local HTTP endpoint catalogue

Bodies below are JSON unless explicitly described as binary. `{}` means no
operation-specific fields. Read-only GETs must not be confused with legacy
state-changing GET routes in section 9.

### Discovery, status and settings

| Method and path | Request | Result / action |
|---|---|---|
| GET `/api/hello` | None | Compact identity/connectivity/capabilities |
| GET `/api/status` | None | Full device/sensor/power/storage/OTA status |
| GET `/api/recording/status` | None | Recording status/health |
| GET `/api/system/diagnostics` | None | `ok`, `system_diagnostics`: boot/reset/watchdog/task history |
| GET `/api/stream/status` | None | Legacy stream state |
| GET `/api/settings` | None | Settings/revision snapshot |
| POST `/api/settings` | Flat settings object | Apply with revision check; may restart |
| GET `/api/sample-rates` | None | `sampleRates` current/default/allowed values |
| POST `/api/sample-rates` | `{"ecg":500,"mic":2000,"imu":125}` | Save rates, scheduled reboot |
| POST `/api/sample-rates/defaults` | `{}` | Restore defaults, reboot |
| POST `/api/power-bank-mode` | `{"enabled":true}` | Keep awake; not automatic power-source detection |
| POST `/api/reconnect-wifi` | `{}` | Reconnect; IP may change |
| POST `/api/restart` | `{}` | Scheduled reboot |
| POST `/api/sleep` | `{}` | Refuses busy recording/storage/OTA; later goes offline |
| GET `/api/usb-msc` | None | Capability and USB mass-storage state |
| POST `/api/usb-msc` | `{"enabled":true}` | Exclusive SD ownership when supported |
| POST `/api/self-test` | `{}` | Start self-test |
| POST `/api/led` | `{"led":"green","enabled":true}` | Manual LED |
| POST `/api/led-heartbeat` | `{}` | Automatic heartbeat |
| POST `/api/led-off-override` | `{"enabled":true}` | Force LEDs off |

Flat device settings: `expectedRevision`, `ecgSampleRate`, `micSampleRate`,
`imuSampleRate`, `powerBankMode`, `ledsOffOverride`, optional `requestId`.
Read revision first; a mismatch is a conflict rather than permission to overwrite.
These flat device fields differ from the cloud settings wrapper.

Supported configured rates: ECG 250/500/1000/2000 Hz; MIC 500/1000/2000 Hz;
IMU selector codes 31/63/125/250 (actual 31.25/62.5/125/250 Hz).
Defaults: ECG 500, MIC 2000, IMU 125. Treat live/header reported rates as data;
do not assume all configurations produce the nominal rate exactly.

Full status includes `deviceId`, `deviceSerial`, `version`, `uptime_ms`, `ip`,
sensor readiness/rates, `logging_channels`, `sdReady`, `sdLogging`, `sdPath`,
`sdSamples`, `sdDropped`, `recording_health`, `system_diagnostics` and `ota`.
Absent fields mean unavailable, not a fabricated zero. `imu_temperature_c` is
an internal sensor temperature, not calibrated skin/contact temperature.

### Recording and files

| Method and path | Request | Result / action |
|---|---|---|
| POST `/api/recording` | `{"mode":"all"}` or booleans `ecg`, `mic`, `imu` | Start selected device recording |
| POST `/api/recording` | `{"mode":"idle"}` | Stop; wait for completion/verification |
| GET `/api/sessions?offset=0&limit=12` | Page query | `sessions`, `hasMore`, `nextOffset` |
| GET `/api/sessions/{id}` | Returned session ID | Session detail |
| GET `/api/sessions/{id}/segments?offset=0&limit=12` | Page query | Segment metadata, paging |
| GET `/api/sessions/{id}/segments/{number}` | Optional HTTP Range | Closed/verified segment binary; numbers start at 1 |
| POST `/api/sessions/rename` | `{"old":"S_OLD","new":"S_NEW"}` | Rename device session directory |
| POST `/api/sessions/delete` | `{"id":"S_TEST"}` | Destructive: delete device recording and segments |
| GET or POST `/api/sessions/sync` | GET none / POST `{}` | Request cloud synchronization/status; unavailable while busy |
| GET `/api/sd/files?offset=0&limit=24` | Page query | Legacy flat file list; `/api/files` alias |
| GET `/api/sd/file?name={encoded-name}` | Name from file list | Legacy raw BIN download |
| POST `/api/sd/rename` | `{"old":"old.bin","new":"new.bin"}` | Rename legacy file |
| POST `/api/sd/delete` | `{"name":"disposable.bin"}` | Destructive: delete legacy file |
| POST `/api/sd/format` | `{"confirm":"FORMAT"}` | Destructive: formats SD; not part of normal integration |
| GET `/api/chunks` | None | Legacy unavailable response; not the v4 file API |

Session metadata includes ID, state, firmware version, serial, rates, size,
duration, segment/verified counts and start time. Segment metadata includes
`number`, `filename`, `state`, `size`, `payloadCrc32`, `startUs`, `endUs`, `gaps`.
Use actual responses rather than inferring names from wall-clock time.

Download sequence:
1. Stop recording and confirm final recording health.
2. Enumerate every session page, then every segment page. Follow hasMore;
   reject a non-advancing cursor. No batch ZIP endpoint exists in this build.
3. Download one segment at a time into a `.part` file.
4. Resume with `Range: bytes=N-`. Append only for valid HTTP 206 with matching
   Content-Range. If the server returns 200, restart from byte zero. Handle 416.
5. Verify expected length and format-v4 header/trailer/payload CRC; rename to
   the final name only after verification. Never save an HTTP JSON error as BIN.
6. Preserve session grouping and original files. A valid CRC proves file
   integrity, not absence of acquisition gaps or physiological artifacts.

## 5. Local live binary protocol (MSLV)

GET `/api/live?ecgAfter=0&micAfter=0&imuAfter=0` returns one binary packet.
GET `/api/live-stream?ecgAfter=...&micAfter=...&imuAfter=...` starts a persistent
HTTP response whose body is repeated `[uint32 length][MSLV packet]` frames.
All integers and floating-unit conversions below use little-endian wire data.
The prefix is not included in packet length. Polling responses have no prefix.

Seed each cursor from the latest accepted sample sequence in the primer packet.
Zero means latest available window, not the start of the recording. Close the
stream to stop preview; this does not stop SD recording. Incrementally consume
network bytes: a TCP read can contain half a frame or several frames. Do not
use an HTTP helper that waits for response EOF for this persistent endpoint.
Bound frame allocation (reference app rejects lengths >16384 or <32 bytes).

### Header (32 bytes)

| Offset | Type | Field |
|---:|---|---|
| 0 | 4 bytes | ASCII `MSLV` |
| 4 | u8 | protocol version: 2 in firmware v16; 1 legacy |
| 5 | u8 | flags |
| 6 | u16 | header bytes |
| 8 | u32 | server timestamp, microseconds |
| 12 | u32 | packet sequence |
| 16,18,20 | u16 each | ECG, MIC, IMU point counts |
| 22 | u16 | reserved |
| 24,26,28 | u16 each | ECG, MIC, IMU rates (rounded) |
| 30 | u16 | reserved |

Flags: 0x01/02/04 ECG/MIC/IMU buffer-ready, 0x08 recording active,
0x10/20/40 corresponding cursor gap. Buffer-ready does not establish good
electrode contact or valid samples; inspect each sample's validity/saturation.

Payload order: all ECG points, then all MIC points, then all IMU points.
Validate exact length: headerBytes + ECGcount*ECGsize + MICcount*12 + IMUcount*16.

| Point | Offset/type | Meaning |
|---|---|---|
| ECG v2, 24 bytes | 0:u32, 4:u32 | sequence, timestampUs |
| | 8:i32 | Legacy differential I-II; this is **not** standard Lead III |
| | 12:u16,14:u8,15:u8 | diagnostic flags, valid, saturation mask |
| | 16:i32,20:i32 | original Lead I and Lead II ADC counts |
| ECG v1, 16 bytes | First 16 bytes above | No separate I/II; cannot recover all three leads |
| MIC, 12 bytes | 0:u32,4:u32,8:i16,10:u8,11:u8 | sequence, timestampUs, raw sample, valid, reserved |
| IMU, 16 bytes | 0:u32,4:u32 | sequence, timestampUs |
| | 8:i16,10:i16,12:i16 | X/Y/Z in milligravity; divide by 1000 for g |
| | 14:u8,15:u8 | diagnostic flags, valid |

Lead III = II-I from the same ECG point. The i32 values contain sign-extended
24-bit ADC values; do not sign-extend them again. For the present 2.4 V reference,
gain 6 configuration: mV = counts * 2400 / (6 * 8388607). Reconfirm the hardware
configuration if using another revision. Saturation bits 0/1 correspond to
channels I/II; derived III requires both. Keep validity separate from value.

Live IMU values are engineering/calibrated values, not original IMU raw counts.
Live preview also omits some SD metadata. Original IMU counts, detailed status
and session diagnostics are available in the SD format, not recoverable from
the lighter live packet alone.

Each stream has independent sequence/timestamps. uint32 microsecond timestamps
wrap about every 71.6 minutes; use modular deltas and a shared epoch, and reset
state on confirmed reboot. Reject duplicates/out-of-order samples and explicitly
mark gaps. Network arrival time is not sample time. Shared timestamps do not
prove common hardware sampling edges or sub-sample ECG-PCG timing accuracy.

Reference parser: `mslv_client.py` beside this guide. It preserves original counts
and reports packet summaries without filtering. Streaming sample rates and
packet counters are not a substitute for a full recording quality assessment.

## 6. SD format and offline analysis

The file starts with a 64-byte `MSLOGB1` header. For v4, recordSize is zero and
the payload is a sequence of typed chunks, not a rectangular ECG-rate table.
Each chunk has a 16-byte header: u8 type, u8 flags, u16 payloadSize,
u32 sequence, u64 sessionUs. Type 1 ECG, 2 MIC, 3 IMU, 4 GAP, 5 diagnostics.
The clean-stop trailer uses `MSENDV4`; use the supplied readers to validate CRC.
SessionUs is a recording-relative 64-bit timestamp, unlike MSLV live uint32 time.

Invalid samples/GAP intervals must remain on their time axis, usually as NaN
in derived arrays. Never compress time or treat repeated/latest values as
new acquisitions. Unknown chunk types can be skipped using payloadSize.
Preserve raw files and create filtered copies only for display/analysis.

Complete released format/readers (part of this handoff):
- [Format-v4 specification](https://github.com/mmarzook3/MotemaSens-SW/blob/v16.0.0/docs/v16.0.0/BINARY_LOG_FORMAT_V4.md)
- [Diagnostic flags](https://github.com/mmarzook3/MotemaSens-SW/blob/v16.0.0/docs/v16.0.0/DIAGNOSTIC_FLAGS.md)
- [GAP definitions](https://github.com/mmarzook3/MotemaSens-SW/blob/v16.0.0/docs/v16.0.0/GAP_EVENTS.md)
- [Python converter and MATLAB readers](https://github.com/mmarzook3/MotemaSens-SW/tree/v16.0.0/motemasens_tools)

## 7. Remote HTTPS API

Use account credentials provided separately. Authenticate with
POST `/api/auth/login`, body `{"username":"<account>","password":"<password>"}`.
Use returned accessToken as `Authorization: Bearer <accessToken>` on account
endpoints. Never embed factory/device secrets in a distributed desktop app.

| Method and route | Contract |
|---|---|
| GET `/health` | Service health, not device-online proof |
| POST `/api/auth/refresh` | `refreshToken`; store returned rotated tokens |
| POST `/api/auth/logout` | `refreshToken`; revoke session |
| POST `/api/auth/register` | Public registration disabled |
| GET `/api/me` | Authenticated account |
| GET `/api/me/devices` or `/api/devices` | Account device list |
| GET `/api/me/devices/{deviceId}` | Device membership/detail |
| DELETE `/api/me/devices/{deviceId}` | Remove account membership, not SD data |
| POST `/api/me/devices/claim-challenge` | `deviceId`, `serialNumber`; returns challengeId, nonce, expiry |
| POST `/api/me/devices/claim` | deviceId, serialNumber, challengeId, proof |
| GET `/api/me/devices/{deviceId}/settings` | Cloud settings + revision |
| PUT `/api/me/devices/{deviceId}/settings` | `{"expectedRevision":N,"settings":{...}}`; stale revision ->409 |
| GET `/api/devices/{deviceId}/status` | Latest device status; check freshness/online |
| POST `/api/devices/{deviceId}/commands` | `command` and fields; requestId <=96 chars, letters/digits/`.`/`_`/`:`/`-` |
| GET `/api/devices/{deviceId}/commands/{commandId}` | Queued command/ack result |
| GET `/api/software/releases` | Available software metadata |
| POST `/api/devices/{deviceId}/ota` | `{"publicVersion":"v16.0.0"}` (or `version` alias); use remote OTA flow below |
| GET `/api/devices/{deviceId}/ota/{updateId}` | Update progress through post-boot confirmation |
| POST `/api/devices/{deviceId}/ota/{updateId}/cancel` | Request cancellation |
| GET `/api/devices/{deviceId}/sd-sessions` | Cloud-synced SD sessions, currently up to 100; not live SD directory |
| GET `/api/devices/{deviceId}/sd-sessions/{sessionId}/segments` | Cloud segment metadata |
| GET `/api/devices/{deviceId}/sd-sessions/{sessionId}/segments/{n}/data` | Verified uploaded segment download |
| GET `/api/devices/{deviceId}/sessions` | Legacy online-log database sessions |
| GET `/api/devices/{deviceId}/sessions/{sessionId}/samples?limit=2000` | Legacy samples; maximum 10000, not MSLV live stream |

Remote command POST acknowledgement means queued, not physically completed.
Poll returned commandId and inspect ack/error, then confirm device status.
Remote shared controls include recording mode/channels/stop, USB log start/stop,
LED controls/self-test, sample rates/defaults/settings, power-bank mode, USB MSC,
WiFi reconnect, restart and sleep. BLE-only claim proof/credential reads are
not a remote desktop credential API. Use the authenticated OTA endpoint rather
than constructing internal `ota_install` payloads.

Claim sequence: request server challenge; send challengeId/nonce to the BLE
`create_claim_proof` command; send returned proof with identity to the server.
The application must not calculate a proof by extracting device secrets.
Cloud settings storage does not imply hardware application; confirm the settings
revision/state on the device after the appropriate command is applied.

Cloud SD routes only contain files already synchronized to the server. They can
return an empty set when storage/database is unavailable; they cannot fetch
unuploaded files from an offline patch. Local remains the direct download path.

### Internal service API inventory (not desktop-client credentials)

For completeness, backend source also exposes device/factory routes:
POST `/api/factory/devices`; GET/POST `/api/factory/ota-cache/{release}`;
GET `/api/ota-candidates/{filename}` (protected download);
POST `/api/devices/{id}/status`; GET `/api/devices/{id}/commands/pending`;
POST `/api/devices/{id}/commands/{commandId}/ack`;
PUT `/api/devices/{id}/sd-sessions/{sessionId}`;
PUT `/api/devices/{id}/sd-sessions/{sessionId}/segments/{n}`;
GET/PUT `/api/devices/{id}/sd-sessions/{sessionId}/segments/{n}/upload`.
They have separate service authentication and deployment contracts. Do not use
them to bypass account membership or simulate another device. Obtain a separate
service-integration contract if building a replacement uploader/factory tool.
Legacy POST `/api/devices/{id}/sessions/{sessionId}/chunks` returns HTTP 410.

## 8. Calibration, credentials and OTA (advanced)

| Local route | Fields / contract |
|---|---|
| GET `/api/imu/calibration` | Sensor configuration, raw/calibrated engineering values and coefficients |
| POST `/api/imu/calibration` | `version`, `date_ymd`, `bias_x/y/z`, `scale_x/y/z`; use measured device-specific calibration |
| POST `/api/imu/calibration/reset` | `{}`; restore default conversion |
| POST `/api/wifi/credentials` | `ssid`, `password`, `requestId`; persists and reconnects |
| POST `/api/wifi/credentials/read` | `{}`; sensitive stored credentials |
| GET `/api/nvs` | Sensitive namespace/key/value inventory; do not collect for routine logs |
| GET `/api/ota/status` | Current update state and limits |
| POST `/api/ota/begin` | updateId, publicVersion, firmwareVersion, sha256, size |
| POST `/api/ota/chunk?updateId=...&offset=N` | Binary firmware bytes; Content-Type application/octet-stream |
| POST `/api/ota/finish` | `{"updateId":"..."}`; checks full size/hash, schedules reboot |
| POST `/api/ota/cancel` | `{}`; abort applicable active transfer |

Local OTA: stop recording; verify approved firmware size/hash before upload;
begin once; read negotiated maxChunkBytes (current maximum 65536; older builds
may need 8192); send sequential chunks at exact accepted offsets; finish; retain
update state across UI navigation and device restart. After an uncertain chunk
response, query progress and reconcile bytesDone rather than blindly advancing.
Final success requires expected firmware version, phase=success,
pendingVerify=false and healthFailureMask=0. Upload completion is not success.
Remote OTA uses the server's selected release and checksum-verified cache;
offline/recording/same-version/downgrade requests can be rejected.
Use the official updater for first integration rather than implementing OTA
as part of a basic plotting client.

## 9. Compatibility routes and USB

Legacy Local routes retained: GET `/status` (status alias), `/stream` (CSV
stream that also starts WiFi logging), `/api/start`, `/api/stop`, `/api/sd/start`,
`/api/sd/stop`, `/api/usb-start`, `/api/usb-stop`, `/api/sd/delete?name=...`,
`/api/sd/rename?old=...&new=...`; `/control?cmd=start|stop|usb-start|usb-stop`.
GET `/` serves a control page; OPTIONS is supported. Prefer JSON POST controls
and MSLV for new applications. Do not prefetch state-changing legacy GET URLs.

USB UART/CDC: 921600 baud, newline-terminated ASCII commands. Read diagnostics
and log lines independently; opening a UART bridge may toggle reset lines.
Supported engineering commands include `DEVICE_SERIAL?`/`SERIAL?`, `SD_STATUS?`,
`BATTERY_STATUS?`, `SYSTEM_DIAG?`, `REMOTE_CONFIG?`, `POWER_BANK_MODE?`,
`USB_MSC_STATUS?`, `S`/`USB_START`, `X`/`USB_STOP`, `SD_START`, `SD_STOP`,
`POWER_BANK_MODE,ON`/`OFF` (or 1/0), `USB_MSC_ON`/`OFF`.
Factory identity/configuration commands and `SYSTEM_WDT_TEST` are service-only;
the latter deliberately triggers a watchdog and must not be part of a recorder.
USB mass-storage support is build/hardware-dependent: query capability first.

## 10. Windows and MATLAB examples

### Windows PowerShell: discovery and status

```powershell
$base = 'http://192.168.1.50' # replace with device's reported IP
$hello = Invoke-RestMethod "$base/api/hello" -TimeoutSec 5
$status = Invoke-RestMethod "$base/api/status" -TimeoutSec 5
$status | Select-Object deviceId, version, sdReady, sdLogging
# Explicit recording command; this writes to device storage when available.
$body = @{mode='all'; requestId=[guid]::NewGuid().ToString()} | ConvertTo-Json
$reply = Invoke-RestMethod "$base/api/recording" -Method Post -ContentType 'application/json' -Body $body
if ($reply.ok -eq $false -or $reply.busy -eq $true) { throw $reply.message }
# Stop: POST the same endpoint with mode='idle' and a new requestId.
```

For Windows C# use HttpClient for finite JSON/file requests and
ResponseHeadersRead for a persistent stream. Implement an incremental MSLV
decoder. BLE can use Windows GATT APIs or an appropriate cross-platform library;
the UUID/JSON contract above is independent of the library.

### MATLAB: finite HTTP requests

```matlab
base = 'http://192.168.1.50'; % replace with discovered IP
opts = weboptions('Timeout', 10, 'ContentType', 'json');
status = webread([base '/api/status'], opts);
sessions = webread([base '/api/sessions?offset=0&limit=12'], opts);
disp(status)
% Explicit recording start; check response and subsequent status.
postOpts = weboptions('Timeout', 10, 'MediaType', 'application/json');
reply = webwrite([base '/api/recording'], struct('mode','all','requestId','matlab-start-001'), postOpts);
% Stop with mode='idle' and a different requestId.
```

For full-file download use MATLAB websave to a temporary filename, then validate
with the supplied v4 reader before renaming. For continuous live view use a
stream-capable HTTP/TCP implementation and the binary layout above, or run the
included Python client as a bridge. webread waiting for EOF is unsuitable.
MATLAB BLE support/toolboxes depend on the installed release and adapter:
discover with blelist, connect with ble, select characteristic by UUID, and
write UTF-8 jsonencode bytes. Do not assume classic serialport can open BLE GATT.
These MATLAB examples are illustrative; MATLAB runtime was not available here.

### MATLAB: BLE identity/status read

```matlab
nearby = blelist;
disp(nearby) % choose the intended device, not simply the first result
device = ble('MotemaSens-ms-0002'); % replace with discovered name/address
service = '9f6d0001-6f2b-4e45-9f2f-6b4f4d53454e';
statusChar = characteristic(device, service, ...
    '9f6d0002-6f2b-4e45-9f2f-6b4f4d53454e');
raw = read(statusChar);
status = jsondecode(native2unicode(uint8(raw(:).'), 'UTF-8'));
disp(status)
% Use status.ip for the Local HTTP examples once WiFi is connected.
clear statusChar device
```

The transport/example checks performed for this guide were source inspection
and `py mslv_client.py --self-test`. The self-test passed v1/v2 layouts, signed
values, III polarity, fragmented/coalesced reads and malformed/oversized packet
length rejection. No physical-device, MATLAB-runtime or cloud-write tests were
performed. The Python example is an integration starting point, not a complete
clinical recorder or automatic recovery/quality-validation implementation.

## 11. Minimum developer acceptance checklist

1. Discover two units without mixing identities; reconnect after IP change.
2. Confirm state-changing response and actual state; simulate timeout/retry.
3. Decode v1/v2 packets, fragmented/coalesced TCP reads, signed extremes,
   timestamp wrap, gaps, saturation and missing modality samples.
4. Start/stop a disposable recording; verify header, trailer, size and CRC.
5. Interrupt/resume a download; never append a 200 response onto a partial file.
6. Export 20-40 files (60-120 MB) sequentially with clear progress and failure
   accounting. This batch workflow is client work, not an existing device ZIP API.
7. Keep raw values immutable; separate display filtering/calibration from data.
8. Test commands while SD/OTA is busy. Never declare operation success from
   transport delivery alone. Check post-reboot identity/version/health.

Implementation references (private engineering repository):
`firmware/mic_waveform_test/src/main.cpp` (routes, BLE, settings, OTA),
`live_preview.cpp/.h` (wire protocol), `ecg_ads1294.cpp` (channel mapping),
`mobile/lib/live_preview.dart` (reference decoder), `segmented_sessions.dart`
(download/CRC), `backend/phase4-api/src/server.js` (cloud API).
Production firmware/app were not modified to prepare this document.
