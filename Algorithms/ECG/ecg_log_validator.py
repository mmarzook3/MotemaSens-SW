#!/usr/bin/env python3
"""Validate MotemaSens ECG timing and raw-record integrity.

This is a public analysis reference. It does not communicate with the device.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path


HEADER = struct.Struct("<8sHHIIB3s40s")
RECORD = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3x")
MAGIC = b"MSLOGB1\x00"


def signed_24(high: int, middle: int, low: int) -> int:
    value = (high << 16) | (middle << 8) | low
    return value - (1 << 24) if value & 0x800000 else value


def validate(path: Path) -> dict[str, object]:
    with path.open("rb") as handle:
        raw_header = handle.read(HEADER.size)
        if len(raw_header) != HEADER.size:
            raise ValueError("file is smaller than the binary header")
        magic, header_size, record_size, format_version, start_ms, channel_mask, _, version = HEADER.unpack(raw_header)
        if magic != MAGIC:
            raise ValueError("missing MSLOGB1 magic")
        if header_size < HEADER.size or record_size != RECORD.size:
            raise ValueError(f"unsupported header/record size: {header_size}/{record_size}")
        if format_version != 1:
            raise ValueError(f"unsupported binary format version: {format_version}")
        if header_size > HEADER.size:
            handle.seek(header_size)

        rows = 0
        first_elapsed = None
        last_elapsed = None
        previous_seq = None
        sequence_gaps = 0
        intervals = []
        previous_ecg_us = None
        min_channels = [math.inf] * 3
        max_channels = [-math.inf] * 3
        lead_off_positive = 0
        lead_off_negative = 0
        saturation = 0

        while True:
            raw = handle.read(RECORD.size)
            if not raw:
                break
            if len(raw) != RECORD.size:
                raise ValueError(f"truncated record at byte {handle.tell() - len(raw)}")
            row = RECORD.unpack(raw)
            elapsed_ms, ecg_us, sequence = row[0], row[1], row[2]
            channels = row[4:7]
            if first_elapsed is None:
                first_elapsed = elapsed_ms
            last_elapsed = elapsed_ms
            if previous_seq is not None and sequence != previous_seq + 1:
                sequence_gaps += 1
            if previous_ecg_us is not None and ecg_us > previous_ecg_us:
                intervals.append(ecg_us - previous_ecg_us)
            for index, value in enumerate(channels):
                min_channels[index] = min(min_channels[index], value)
                max_channels[index] = max(max_channels[index], value)
            lead_off_positive += row[19] != 0
            lead_off_negative += row[20] != 0
            saturation += row[21] != 0
            previous_seq = sequence
            previous_ecg_us = ecg_us
            rows += 1

    median_interval = sorted(intervals)[len(intervals) // 2] if intervals else None
    return {
        "file": str(path),
        "firmware_version": version.split(b"\x00", 1)[0].decode("ascii", errors="replace"),
        "header_size": header_size,
        "record_size": record_size,
        "format_version": format_version,
        "start_ms": start_ms,
        "channel_mask": channel_mask,
        "records": rows,
        "duration_s": round((last_elapsed or 0) / 1000.0, 3),
        "median_ecg_interval_us": median_interval,
        "observed_ecg_rate_hz": round(1_000_000 / median_interval, 3) if median_interval else None,
        "sequence_gaps": sequence_gaps,
        "lead_min": min_channels,
        "lead_max": max_channels,
        "lead_off_positive_records": lead_off_positive,
        "lead_off_negative_records": lead_off_negative,
        "saturation_records": saturation,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.files:
        try:
            report = validate(path)
            print(json.dumps(report, indent=2))
            failed |= report["sequence_gaps"] != 0
        except (OSError, ValueError) as error:
            print(f"{path}: ERROR: {error}", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
