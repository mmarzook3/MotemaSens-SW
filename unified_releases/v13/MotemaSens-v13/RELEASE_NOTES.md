# MotemaSens v13 release notes

MotemaSens v13 is the high-rate reliability release: firmware, Android app,
desktop tools, documentation and package metadata use the same version.

Highlights:

- ECG supports 250, 500, 1,000 and 2,000 Hz; microphone supports up to 2,000 Hz
  and IMU supports up to 250 Hz.
- ECG startup uses a verified reset/ID retry and faster continuous SPI reads.
- Microphone DMA overflow/error events are visible as explicit source gaps.
- IMU acquisition is independent from the highest-priority ECG path.
- Recording start/stop is acknowledged by the acquisition core before the app
  reports success.
- SD browsing and software updates are locked during recording.
- Session diagnostics include queue, stall, SD and stream-boundary evidence.
- Recordings receive one quality result: complete, minor loss, failed or
  unverified.
- Python, Flutter and MATLAB readers share the same v4 channel, gap, checksum
  and quality rules.
- Raw ECG channels are clearly named and Lead III is derived as Lead II minus
  Lead I.
- Invalid and missing values remain visible as `NaN` rather than being hidden.
- The phone live view now renders smooth ECG, heart-sound microphone and IMU
  waveforms without changing the raw values saved to the SD card.
- Local-IP streaming remains responsive while SD recording is active, with
  bounded history and explicit connection, pause and error states in the app.
- Active SD recordings use `.bin.part`, interrupted files are retained as
  incomplete, and `.bin` is produced only after trailer/CRC verification.
- Long SD verification and downloads yield cooperatively instead of starving
  Core 1.
- The app streams large downloads to disk and checkpoints live recordings.
- Python, Flutter and MATLAB readers reconstruct timestamps from the rate
  metadata stored in each v4 file.
- Firmware, Android app, BIN-to-CSV, MATLAB viewer, USB logger, updater and user
  documentation are supplied together as one versioned package.

Automated builds, parser tests, connected-phone installation, Local IP control,
OTA and physical ESP32/SD tests passed. The maximum physical profile was
ECG/MIC/IMU `2000/2000/250 Hz`; the clean-stop file had zero explicit gaps,
queue drops, invalid session frames or overruns and passed trailer/CRC checks.
MATLAB runtime execution was not available in this release environment, so the
static cross-reader contract was used and this limitation is recorded.
