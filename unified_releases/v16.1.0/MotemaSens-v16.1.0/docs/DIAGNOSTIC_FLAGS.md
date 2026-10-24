# MotemaSens ECG diagnostic flags

The `diag_flags` field is a bit mask. More than one flag may be present.

| Value | Meaning |
| --- | --- |
| `0x0001` | Lead contact is off or poor. |
| `0x0002` | ECG input is saturated or clipped. |
| `0x0004` | Common-mode or cable-noise warning. |
| `0x0008` | Sustained common-mode stability warning. |
| `0x0010` | Bias/common-mode control configuration was verified at startup. |
| `0x0020` | Lead-contact detection configuration was verified at startup. |
| `0x0040` | ECG frame failed its integrity check. |
| `0x0080` | At least one ECG acquisition event was missed before reading. |
| `0x0100` | Startup register readback did not match the requested configuration. |

`0x0030` means both startup configuration checks passed. It is not an error.
Invalid ECG samples remain in the timeline with their diagnostic metadata, but
their signal values are exported as `NaN`.
