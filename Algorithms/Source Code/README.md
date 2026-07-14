# MotemaSens ECG Firmware

This ESP-IDF firmware implements the MotemaSens ECG acquisition and binary logging path. It uses DRDY-triggered reads, 24-bit signed conversion, diagnostics, bounded buffering, and fixed-size SD records.

## Project layout

- `main/` owns startup and FreeRTOS task creation.
- `components/board/` contains board pin definitions and hardware setup.
- `components/ecg/` contains ECG register control, SPI transport, frame decoding, diagnostics, filtering, and the acquisition task.
- `components/storage/` contains the binary record definition, ring buffer, and SD writer.
- `components/system/` contains health and telemetry state shared by the application.
- `components/common/` contains shared configuration, types, and status codes.

## Recording path

`DRDY ISR -> ECG task -> SPI frame read -> signed 24-bit conversion -> diagnostics -> queue -> binary SD record`

The storage record retains signed acquisition samples. Display-oriented filtering is separate from the stored samples, so rendering does not alter the raw ECG samples written to a recording.

## ESP-IDF build

Install ESP-IDF, set up its environment, then from this folder run:

```text
idf.py set-target esp32s3
idf.py build
```

Confirm the board pin assignments and target configuration before building and flashing the firmware.
