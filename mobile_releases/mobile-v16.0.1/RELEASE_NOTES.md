# MotemaSens Android app 16.0.1

App-only patch. Firmware and analysis tools remain v16.0.0; no firmware update
is required. Install this APK over the existing app to preserve its recordings.

## Fix

Downloaded SD recording sessions were verified and kept in private app storage,
so they were not visible in Android Files / My Files. Session download now says
explicitly where the files are stored. New controls export selected segments:

- Save icon: copy verified files into the phone's public Downloads folder.
- Share icon: open Android's share sheet with the selected verified BIN files.
- Open Downloads: open the phone's Downloads browser after saving.

Exported names include the session ID, for example
`S_Chest_SEG_000001.bin`. Existing private copies are retained. Previously
downloaded sessions can be exported after reopening the session; they do not
need to be downloaded again if all selected local segments still verify.
Missing, partial or corrupt segments are rejected. A failed export reports how
many files were saved. Large copies run off Android's UI thread.

## How to use

1. Install app 16.0.1 without uninstalling the current app or clearing its data.
2. Open Storage and the recording session. Select the segments you need.
3. Download missing segments, then tap Save or Share.
4. After Save, choose Open Downloads, or use Files / My Files > Downloads and
   search for the session ID. Raw BIN files need a compatible analysis tool;
   Android's file browser may not offer a BIN viewer.

Individual legacy BIN downloads continue to save directly to Downloads.
This change does not delete files on the device SD card or alter raw data.
