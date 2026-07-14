# ECG component map

| Module | Responsibility |
| --- | --- |
| `ads129x_spi.c` | SPI host, command sequence, register writes, and continuous-read start. |
| `ads129x_registers.c` | Register policy descriptions for the acquisition configuration. |
| `ads129x_frame.c` | Status word capture and sign extension of four 24-bit samples. |
| `ecg_diagnostics.c` | Saturation and lead-status interpretation. |
| `ecg_filter.c` | Display-only baseline removal and scaling. It does not change stored raw samples. |
| `ecg_pipeline.c` | Bounded FreeRTOS acquisition queue. |
| `ecg_task.c` | DRDY notification, sample sequencing, queue publication, and storage hand-off. |

The key frame invariant is `3 status bytes + 4 * 3 channel bytes = 15 bytes` per DRDY event.
