from __future__ import annotations

import argparse
import csv
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Iterable


MAGIC = b"MSLOGB1\x00"
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
]

HEADER_STRUCT = struct.Struct("<8sHHIIB3s40s")
RECORD_STRUCT = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3x")
RECORD_STRUCT_V2 = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3xII4h")


@dataclass(frozen=True)
class BinaryLogHeader:
    header_size: int
    record_size: int
    format_version: int
    start_ms: int
    channel_mask: int
    firmware_version: str


def read_header(handle: BinaryIO) -> BinaryLogHeader:
    raw = handle.read(HEADER_STRUCT.size)
    if len(raw) != HEADER_STRUCT.size:
        raise ValueError("File is too small to be a MotemaSens binary log")

    magic, header_size, record_size, format_version, start_ms, channel_mask, _, version = HEADER_STRUCT.unpack(raw)
    if magic != MAGIC:
        raise ValueError("Not a MotemaSens binary log: missing MSLOGB1 magic")
    if header_size < HEADER_STRUCT.size:
        raise ValueError(f"Bad header size: {header_size}")
    expected_record_size = RECORD_STRUCT_V2.size if format_version == 2 else RECORD_STRUCT.size
    if record_size != expected_record_size:
        raise ValueError(f"Bad record size: {record_size}")
    if format_version not in (1, 2):
        raise ValueError(f"Unsupported binary log version: {format_version}")

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


def iter_csv_rows(handle: BinaryIO) -> Iterable[list[str]]:
    header = read_header(handle)
    record_struct = RECORD_STRUCT_V2 if header.format_version == 2 else RECORD_STRUCT
    while True:
        raw = handle.read(record_struct.size)
        if not raw:
            break
        if len(raw) != record_struct.size:
            break

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
        ) = RECORD_STRUCT.unpack(raw[:RECORD_STRUCT.size])

        mic_first_us = ""
        mic_sequence = ""
        mic_raw = ["", "", "", ""]
        if header.format_version == 2:
            mic_first_value, mic_sequence_value, *mic_raw_values = RECORD_STRUCT_V2.unpack(raw)[25:]
            mic_first_us = str(mic_first_value)
            mic_sequence = str(mic_sequence_value)
            mic_raw = [f"{value / 32767.0:.4f}" for value in mic_raw_values]

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
    rows = convert_file(args.source, destination, overwrite=args.overwrite)
    print(f"Converted {rows} rows: {args.source} -> {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
