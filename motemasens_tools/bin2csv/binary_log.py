from __future__ import annotations

import argparse
import csv
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Iterable


MAGIC = b"MSLOGB1\x00"
TRAILER_MAGIC_V3 = b"MSENDV3\x00"

MIC_BLOCK_REASONS = {
    0: "complete",
    1: "disabled",
    2: "startup_sync",
    3: "queue_underflow",
    4: "queue_drop",
    5: "ring_drop",
    6: "source_gap",
}

CSV_HEADER = [
    "LOG_HEADER",
    "ms",
    "ecg_us",
    "ecg_seq8",
    "ecg_seq",
    "ecg_status",
    "lead_i_raw",
    "lead_ii_raw",
    "lead_iii_raw",
    "lead_off_p",
    "lead_off_n",
    "sat_mask",
    "diag_flags",
    "mic_ms",
    "mic_seq8",
    "mic_trace",
    "mic_level",
    "mic_first_us",
    "mic_sample_seq",
    "mic_raw_0",
    "mic_raw_1",
    "mic_raw_2",
    "mic_raw_3",
    "acc_ms",
    "acc_seq8",
    "acc_x_g",
    "acc_y_g",
    "acc_z_g",
    "raw_x",
    "raw_y",
    "raw_z",
    "acc_diag_flags",
    "mic_block_valid_mask",
    "mic_missing_count",
    "mic_block_reason",
    "imu_valid",
    "imu_age_us",
    "imu_sample_seq",
    "log_format_version",
]

HEADER_STRUCT = struct.Struct("<8sHHIIB3s40s")
RECORD_STRUCT = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3x")
RECORD_STRUCT_V2 = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3xII4h")
RECORD_STRUCT_V3 = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3xII4hBBBBII")
TRAILER_STRUCT_V3 = struct.Struct("<8sHH11I40s")


@dataclass(frozen=True)
class BinaryLogHeader:
    header_size: int
    record_size: int
    format_version: int
    start_ms: int
    channel_mask: int
    firmware_version: str


@dataclass(frozen=True)
class BinaryLogTrailer:
    record_count: int
    elapsed_ms: int
    payload_crc32: int
    ecg_invalid_frames: int
    ecg_acquisition_overruns: int
    mic_samples_acquired: int
    mic_frame_queue_drops: int
    mic_log_underflows: int
    mic_log_ring_drops: int
    mic_source_gap_samples: int
    imu_samples: int
    sd_dropped_records: int
    ecg_frames_received: int
    ecg_saturation_events: int
    ecg_lead_off_events: int
    ecg_cable_noise_events: int
    ecg_rld_unstable_events: int
    ecg_register_readback_mismatches: int
    ecg_config_flags: int
    imu_missed_updates: int
    imu_poll_failures: int


@dataclass(frozen=True)
class BinaryLogInfo:
    header: BinaryLogHeader
    record_count: int
    complete: bool
    crc_valid: bool | None
    trailer: BinaryLogTrailer | None
    trailing_bytes: int
    status: str


def _record_struct(format_version: int) -> struct.Struct:
    formats = {
        1: RECORD_STRUCT,
        2: RECORD_STRUCT_V2,
        3: RECORD_STRUCT_V3,
    }
    try:
        return formats[format_version]
    except KeyError as exc:
        raise ValueError(f"Unsupported binary log version: {format_version}") from exc


def read_header(handle: BinaryIO) -> BinaryLogHeader:
    raw = handle.read(HEADER_STRUCT.size)
    if len(raw) != HEADER_STRUCT.size:
        raise ValueError("File is too small to be a MotemaSens binary log")

    magic, header_size, record_size, format_version, start_ms, channel_mask, _, version = HEADER_STRUCT.unpack(raw)
    if magic != MAGIC:
        raise ValueError("Not a MotemaSens binary log: missing MSLOGB1 magic")
    if header_size < HEADER_STRUCT.size:
        raise ValueError(f"Bad header size: {header_size}")

    expected_record_size = _record_struct(format_version).size
    if record_size != expected_record_size:
        raise ValueError(
            f"Bad record size: format v{format_version} requires {expected_record_size}, got {record_size}"
        )

    if header_size > HEADER_STRUCT.size:
        handle.seek(header_size)

    return BinaryLogHeader(
        header_size=header_size,
        record_size=record_size,
        format_version=format_version,
        start_ms=start_ms,
        channel_mask=channel_mask,
        firmware_version=version.split(b"\x00", 1)[0].decode("ascii", errors="replace"),
    )


def _stream_crc32(handle: BinaryIO, offset: int, size: int) -> int:
    handle.seek(offset)
    crc = 0
    remaining = size
    while remaining:
        block = handle.read(min(65536, remaining))
        if not block:
            break
        crc = zlib.crc32(block, crc)
        remaining -= len(block)
    return crc & 0xFFFFFFFF


def inspect_handle(handle: BinaryIO, header: BinaryLogHeader) -> BinaryLogInfo:
    handle.seek(0, 2)
    file_size = handle.tell()
    if file_size < header.header_size:
        raise ValueError("Binary log header extends beyond the end of the file")

    payload_size = file_size - header.header_size
    data_size = payload_size
    trailer: BinaryLogTrailer | None = None
    complete = False
    crc_valid: bool | None = None
    status = "incomplete: clean-stop trailer missing"

    if header.format_version == 3 and payload_size >= TRAILER_STRUCT_V3.size:
        handle.seek(file_size - TRAILER_STRUCT_V3.size)
        raw_trailer = handle.read(TRAILER_STRUCT_V3.size)
        unpacked = TRAILER_STRUCT_V3.unpack(raw_trailer)
        magic, trailer_size, trailer_version, *values, reserved = unpacked
        if magic == TRAILER_MAGIC_V3:
            data_size = payload_size - TRAILER_STRUCT_V3.size
            if trailer_size != TRAILER_STRUCT_V3.size or trailer_version != 3:
                status = "incomplete: invalid v3 trailer header"
            else:
                (
                    record_count,
                    elapsed_ms,
                    payload_crc32,
                    ecg_invalid_frames,
                    ecg_acquisition_overruns,
                    mic_samples_acquired,
                    mic_frame_queue_drops,
                    mic_log_underflows,
                    mic_log_ring_drops,
                    imu_samples,
                    sd_dropped_records,
                ) = values
                (
                    mic_source_gap_samples,
                    ecg_frames_received,
                    ecg_saturation_events,
                    ecg_lead_off_events,
                    ecg_cable_noise_events,
                    ecg_rld_unstable_events,
                    ecg_register_readback_mismatches,
                    ecg_config_flags,
                    imu_missed_updates,
                    imu_poll_failures,
                ) = struct.unpack_from("<10I", reserved)
                trailer = BinaryLogTrailer(
                    record_count=record_count,
                    elapsed_ms=elapsed_ms,
                    payload_crc32=payload_crc32,
                    ecg_invalid_frames=ecg_invalid_frames,
                    ecg_acquisition_overruns=ecg_acquisition_overruns,
                    mic_samples_acquired=mic_samples_acquired,
                    mic_frame_queue_drops=mic_frame_queue_drops,
                    mic_log_underflows=mic_log_underflows,
                    mic_log_ring_drops=mic_log_ring_drops,
                    mic_source_gap_samples=mic_source_gap_samples,
                    imu_samples=imu_samples,
                    sd_dropped_records=sd_dropped_records,
                    ecg_frames_received=ecg_frames_received,
                    ecg_saturation_events=ecg_saturation_events,
                    ecg_lead_off_events=ecg_lead_off_events,
                    ecg_cable_noise_events=ecg_cable_noise_events,
                    ecg_rld_unstable_events=ecg_rld_unstable_events,
                    ecg_register_readback_mismatches=ecg_register_readback_mismatches,
                    ecg_config_flags=ecg_config_flags,
                    imu_missed_updates=imu_missed_updates,
                    imu_poll_failures=imu_poll_failures,
                )
                calculated_crc = _stream_crc32(handle, header.header_size, data_size)
                crc_valid = calculated_crc == trailer.payload_crc32
                expected_records, trailing_bytes = divmod(data_size, header.record_size)
                complete = crc_valid and trailing_bytes == 0 and expected_records == trailer.record_count
                if complete:
                    status = "complete: clean stop trailer and payload CRC verified"
                elif not crc_valid:
                    status = "incomplete: v3 payload CRC mismatch"
                elif trailing_bytes:
                    status = "incomplete: bytes remain before v3 trailer"
                else:
                    status = "incomplete: v3 trailer record count mismatch"

    record_count, trailing_bytes = divmod(data_size, header.record_size)
    return BinaryLogInfo(
        header=header,
        record_count=record_count,
        complete=complete,
        crc_valid=crc_valid,
        trailer=trailer,
        trailing_bytes=trailing_bytes,
        status=status,
    )


def inspect_file(source: Path) -> BinaryLogInfo:
    with source.open("rb") as handle:
        header = read_header(handle)
        return inspect_handle(handle, header)


def iter_csv_rows(handle: BinaryIO) -> Iterable[list[str]]:
    header = read_header(handle)
    info = inspect_handle(handle, header)
    record_struct = _record_struct(header.format_version)
    handle.seek(header.header_size)

    for _ in range(info.record_count):
        raw = handle.read(record_struct.size)
        if len(raw) != record_struct.size:
            break
        base = RECORD_STRUCT.unpack(raw[:RECORD_STRUCT.size])
        (
            elapsed_ms,
            ecg_us,
            ecg_seq,
            ecg_status,
            lead_i,
            lead_ii,
            lead_iii,
            mic_ms,
            acc_ms,
            mic_trace_q15,
            mic_level_q15,
            acc_x_mg,
            acc_y_mg,
            acc_z_mg,
            raw_x,
            raw_y,
            raw_z,
            diag_flags,
            ecg_seq8,
            lead_off_p,
            lead_off_n,
            sat_mask,
            mic_seq8,
            acc_seq8,
            acc_diag_flags,
        ) = base

        mic_first_us = ""
        mic_sequence = ""
        mic_raw = ["", "", "", ""]
        mic_valid_mask = ""
        mic_missing_count = ""
        mic_block_reason = ""
        imu_valid = ""
        imu_age_us = ""
        imu_sequence = ""

        if header.format_version >= 2:
            v2_values = RECORD_STRUCT_V2.unpack(raw[:RECORD_STRUCT_V2.size])
            mic_first_us = str(v2_values[25])
            mic_sequence = str(v2_values[26])
            mic_raw = [f"{value / 32767.0:.4f}" for value in v2_values[27:31]]

        if header.format_version == 3:
            v3_values = RECORD_STRUCT_V3.unpack(raw)
            mic_valid_mask_value, mic_missing_value, mic_reason_value, imu_valid_value, imu_age_value, imu_sequence_value = v3_values[31:]
            mic_valid_mask = f"{mic_valid_mask_value:02X}"
            mic_missing_count = str(mic_missing_value)
            mic_block_reason = MIC_BLOCK_REASONS.get(mic_reason_value, f"unknown_{mic_reason_value}")
            imu_valid = str(imu_valid_value)
            imu_age_us = str(imu_age_value)
            imu_sequence = str(imu_sequence_value)

        yield [
            "LOG",
            str(elapsed_ms),
            str(ecg_us),
            str(ecg_seq8),
            str(ecg_seq),
            f"{ecg_status:06X}",
            str(lead_i),
            str(lead_ii),
            str(lead_iii),
            f"{lead_off_p:02X}",
            f"{lead_off_n:02X}",
            f"{sat_mask:02X}",
            f"{diag_flags:04X}",
            str(mic_ms),
            str(mic_seq8),
            f"{mic_trace_q15 / 32767.0:.4f}",
            f"{mic_level_q15 / 32767.0:.4f}",
            mic_first_us,
            mic_sequence,
            *mic_raw,
            str(acc_ms),
            str(acc_seq8),
            f"{acc_x_mg / 1000.0:.4f}",
            f"{acc_y_mg / 1000.0:.4f}",
            f"{acc_z_mg / 1000.0:.4f}",
            str(raw_x),
            str(raw_y),
            str(raw_z),
            f"{acc_diag_flags:02X}",
            mic_valid_mask,
            mic_missing_count,
            mic_block_reason,
            imu_valid,
            imu_age_us,
            imu_sequence,
            str(header.format_version),
        ]


def convert_file(source: Path, destination: Path, overwrite: bool = False) -> int:
    if not source.exists():
        raise FileNotFoundError(source)
    if destination.exists() and not overwrite:
        raise FileExistsError(destination)

    row_count = 0
    with source.open("rb") as src, destination.open("w", newline="", encoding="utf-8") as dst:
        writer = csv.writer(dst)
        writer.writerow(CSV_HEADER)
        for row in iter_csv_rows(src):
            writer.writerow(row)
            row_count += 1
    return row_count


def default_destination(source: Path) -> Path:
    return source.with_suffix(".csv")


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert MotemaSens binary SD logs to CSV.")
    parser.add_argument("source", type=Path, help="Input .bin file from the SD card")
    parser.add_argument("destination", type=Path, nargs="?", help="Output .csv file")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite output CSV if it already exists")
    args = parser.parse_args()

    destination = args.destination or default_destination(args.source)
    info = inspect_file(args.source)
    rows = convert_file(args.source, destination, overwrite=args.overwrite)
    print(f"Converted {rows} rows: {args.source} -> {destination}")
    print(f"Session status: {info.status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
