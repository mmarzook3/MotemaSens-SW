from __future__ import annotations

import csv
import struct
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from binary_log import CSV_HEADER_V4, BinaryLogInfo, inspect_file, iter_csv_rows


INDEX_MAGIC = b"MSIDX1\x00\x00"
JOURNAL_MAGIC = b"MSJR"
INDEX_HEADER = struct.Struct("<8sHHHH32sIB3xIIIQQ40sI")
INDEX_RECORD = struct.Struct("<4sHHIBBHIIQQQQQI3I3I3Q3Q3QHHQ40sI")

SESSION_STARTED = 1
SEGMENT_OPENED = 2
SEGMENT_CLOSED = 3
SEGMENT_VERIFIED = 4
SEGMENT_INCOMPLETE = 5
SESSION_COMPLETED = 6
SESSION_FAILED = 7

STATE_NAMES = {
    0: "none",
    1: "open",
    2: "closed",
    3: "verified",
    4: "incomplete",
    5: "failed",
}


@dataclass
class SessionSegment:
    number: int
    state: str = "none"
    reason: int = 0
    filename: str = ""
    size: int = 0
    payload_crc32: int = 0
    start_us: int = 0
    end_us: int = 0
    first_sequence: tuple[int, int, int] = (0, 0, 0)
    last_sequence: tuple[int, int, int] = (0, 0, 0)
    first_timestamp_us: tuple[int, int, int] = (0, 0, 0)
    last_timestamp_us: tuple[int, int, int] = (0, 0, 0)
    gaps: tuple[int, int, int] = (0, 0, 0)


@dataclass
class SessionIndex:
    directory: Path
    session_id: str
    device_serial: int
    channel_mask: int
    ecg_rate_hz: int
    mic_rate_hz: int
    imu_rate_hz: int
    start_monotonic_us: int
    start_utc_ms: int
    firmware_version: str
    completed: bool = False
    failed: bool = False
    journal_records: int = 0
    segments: dict[int, SessionSegment] = field(default_factory=dict)

    @property
    def duration_us(self) -> int:
        return max((segment.end_us for segment in self.segments.values()), default=0)

    @property
    def total_bytes(self) -> int:
        return sum(segment.size for segment in self.segments.values())


@dataclass(frozen=True)
class SessionValidation:
    valid: bool
    status: str
    segment_results: tuple[tuple[int, BinaryLogInfo], ...]
    errors: tuple[str, ...]


def _crc_valid(raw: bytes) -> bool:
    expected = struct.unpack_from("<I", raw, len(raw) - 4)[0]
    candidate = bytearray(raw)
    candidate[-4:] = b"\x00\x00\x00\x00"
    return zlib.crc32(candidate) & 0xFFFFFFFF == expected


def _text(raw: bytes) -> str:
    return raw.split(b"\x00", 1)[0].decode("utf-8", errors="replace")


def read_session_index(directory: Path) -> SessionIndex:
    path = directory / "session.msidx"
    with path.open("rb") as handle:
        raw_header = handle.read(INDEX_HEADER.size)
        if len(raw_header) != INDEX_HEADER.size or not _crc_valid(raw_header):
            raise ValueError(f"Invalid session index header: {path}")
        (
            magic,
            schema,
            header_size,
            record_size,
            log_format,
            session_id,
            device_serial,
            channel_mask,
            ecg_rate,
            mic_rate,
            imu_rate,
            start_monotonic_us,
            start_utc_ms,
            firmware,
            _header_crc,
        ) = INDEX_HEADER.unpack(raw_header)
        if (
            magic != INDEX_MAGIC
            or schema != 1
            or header_size != INDEX_HEADER.size
            or record_size != INDEX_RECORD.size
            or log_format != 4
        ):
            raise ValueError(f"Unsupported session index contract: {path}")
        index = SessionIndex(
            directory=directory,
            session_id=_text(session_id),
            device_serial=device_serial,
            channel_mask=channel_mask,
            ecg_rate_hz=ecg_rate,
            mic_rate_hz=mic_rate,
            imu_rate_hz=imu_rate,
            start_monotonic_us=start_monotonic_us,
            start_utc_ms=start_utc_ms,
            firmware_version=_text(firmware),
        )

        last_journal_sequence = 0
        while True:
            raw = handle.read(INDEX_RECORD.size)
            if not raw:
                break
            if len(raw) != INDEX_RECORD.size or not _crc_valid(raw):
                raise ValueError(f"Truncated or corrupt session journal: {path}")
            values = INDEX_RECORD.unpack(raw)
            (
                record_magic,
                record_schema,
                record_size,
                journal_sequence,
                record_type,
                state,
                reason,
                segment_number,
                _flags,
                _start_monotonic,
                _end_monotonic,
                start_session_us,
                end_session_us,
                file_size,
                payload_crc,
                *tail,
            ) = values
            if record_magic != JOURNAL_MAGIC or record_schema != 1 or record_size != INDEX_RECORD.size:
                raise ValueError(f"Unsupported session journal record: {path}")
            if journal_sequence <= last_journal_sequence:
                raise ValueError(f"Non-monotonic journal sequence in {path}")
            last_journal_sequence = journal_sequence
            index.journal_records += 1
            if record_type == SESSION_COMPLETED:
                index.completed = True
            elif record_type == SESSION_FAILED:
                index.failed = True
            if segment_number == 0:
                continue

            first_sequences = tuple(tail[0:3])
            last_sequences = tuple(tail[3:6])
            first_timestamps = tuple(tail[6:9])
            last_timestamps = tuple(tail[9:12])
            gaps = tuple(tail[12:15])
            filename = _text(tail[18])
            segment = index.segments.setdefault(segment_number, SessionSegment(segment_number))
            segment.state = STATE_NAMES.get(state, f"unknown_{state}")
            segment.reason = reason
            segment.filename = filename
            segment.size = file_size
            segment.payload_crc32 = payload_crc
            segment.start_us = start_session_us
            segment.end_us = end_session_us
            segment.first_sequence = first_sequences
            segment.last_sequence = last_sequences
            segment.first_timestamp_us = first_timestamps
            segment.last_timestamp_us = last_timestamps
            segment.gaps = gaps
    return index


def validate_session(directory: Path) -> SessionValidation:
    index = read_session_index(directory)
    errors: list[str] = []
    results: list[tuple[int, BinaryLogInfo]] = []
    previous_last_us = [None, None, None]
    previous_last_sequence = [None, None, None]

    for number, segment in sorted(index.segments.items()):
        if segment.state != "verified":
            errors.append(f"segment {number} is {segment.state}, not verified")
            continue
        path = directory / segment.filename
        if not path.exists():
            errors.append(f"segment {number} is missing: {segment.filename}")
            continue
        if path.stat().st_size != segment.size:
            errors.append(f"segment {number} size differs from session index")
        info = inspect_file(path)
        results.append((number, info))
        if not info.complete or not info.crc_valid:
            errors.append(f"segment {number} failed v4 trailer/CRC validation")
        if info.trailer and info.trailer.payload_crc32 != segment.payload_crc32:
            errors.append(f"segment {number} CRC differs from session index")
        for stream in range(3):
            first_us = segment.first_timestamp_us[stream]
            first_sequence = segment.first_sequence[stream]
            if previous_last_us[stream] is not None and first_us and first_us < previous_last_us[stream]:
                errors.append(f"segment {number} stream {stream + 1} timestamp regressed")
            if (
                previous_last_sequence[stream] is not None
                and first_sequence
                and ((first_sequence - previous_last_sequence[stream]) & 0xFFFFFFFF) > 0x7FFFFFFF
            ):
                errors.append(f"segment {number} stream {stream + 1} sequence regressed")
            if segment.last_timestamp_us[stream]:
                previous_last_us[stream] = segment.last_timestamp_us[stream]
            if segment.last_sequence[stream]:
                previous_last_sequence[stream] = segment.last_sequence[stream]

    if not index.completed:
        errors.append("session has no completed journal record")
    if index.failed:
        errors.append("session contains a failed journal record")
    status = "complete: all session segments and CRCs verified" if not errors else "; ".join(errors)
    return SessionValidation(not errors, status, tuple(results), tuple(errors))


def iter_session_rows(directory: Path) -> Iterable[list[str]]:
    index = read_session_index(directory)
    for number, segment in sorted(index.segments.items()):
        if segment.state != "verified":
            continue
        with (directory / segment.filename).open("rb") as handle:
            yield from iter_csv_rows(handle)


def convert_session(directory: Path, destination: Path, overwrite: bool = False) -> int:
    if destination.exists() and not overwrite:
        raise FileExistsError(destination)
    validation = validate_session(directory)
    if not validation.valid:
        raise ValueError(validation.status)
    rows = 0
    with destination.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(CSV_HEADER_V4)
        for row in iter_session_rows(directory):
            writer.writerow(row)
            rows += 1
    return rows

