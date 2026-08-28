# MotemaSens v14.0.1 test summary

Automated and available physical-device gates passed. Publication was explicitly approved with limitations by Mohamed Marzook.

Known validation limitations:

- Firmware v14.0.1 and app 14.0.1+97 were built and statically verified but were not installed on physical devices before publication by explicit request.
- Runtime behavior is unchanged from the physically validated v14.0.0 release; only unified version metadata changed.
- MATLAB runtime validation remains deferred because MATLAB is unavailable on the release workstation.
- USB mass storage still requires revised native-USB hardware; current devices use Local WiFi download.

Reason: This is a version-only patch release requested specifically for a manual VPS software-update trial. The user instructed that no app or firmware artifact be installed on connected devices before publication.

Evidence: release/public_docs/RELEASE_NOTES.md.
