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
TRAILER_MAGIC_V4 = b"MSENDV4\x00"

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
    "ecg_valid",
    "ecg_ch1_raw",
    "ecg_ch2_raw",
    "ecg_ch3_raw",
    "ecg_ch4_raw",
    "lead_i",
    "lead_ii",
    "lead_iii_derived",
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

# v4 stores each acquired stream independently.  This avoids inventing
# repeated microphone/IMU values to fit a fixed ECG-rate record.
CSV_HEADER_V4 = [
    "LOG_HEADER", "stream", "session_us", "sequence", "valid",
    "ecg_status", "ecg_ch1_raw", "ecg_ch2_raw", "ecg_ch3_raw", "ecg_ch4_raw",
    "lead_i", "lead_ii", "lead_iii_derived",
    "lead_off_p", "lead_off_n", "sat_mask", "diag_flags", "frame_read_delay_us",
    "mic_block_sample_count", "mic_block_sample_index", "mic_sample",
    "imu_x_g", "imu_y_g", "imu_z_g",
    "raw_x", "raw_y", "raw_z", "imu_diag_flags", "gap_stream", "gap_reason",
    "gap_missing_samples", "gap_expected_sequence", "gap_next_sequence", "missing_index",
    "session_quality", "diagnostics_schema", "core1_max_stall_us", "core1_max_busy_us",
    "sd_max_write_us", "ecg_queue_high_water", "mic_queue_high_water", "imu_queue_high_water",
    "storage_operations_rejected", "start_ack_us", "stop_ack_us",
    "discarded_pre_session_ecg", "discarded_pre_session_mic", "discarded_pre_session_imu",
    "ecg_queue_dropped", "mic_queue_dropped", "imu_queue_dropped", "sd_write_failures",
    "ecg_first_sequence", "ecg_last_sequence", "ecg_first_us", "ecg_last_us",
    "mic_first_sequence", "mic_last_sequence", "mic_first_us", "mic_last_us",
    "imu_first_sequence", "imu_last_sequence", "imu_first_us", "imu_last_us",
    "log_format_version",
]

V4_VALUE_KEYS = CSV_HEADER_V4[5:-1]

HEADER_STRUCT = struct.Struct("<8sHHIIB3s40s")
RECORD_STRUCT = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3x")
RECORD_STRUCT_V2 = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3xII4h")
RECORD_STRUCT_V3 = struct.Struct("<IIIIiiiIIhhhhhhhhHBBBBBBB3xII4hBBBBII")
TRAILER_STRUCT_V3 = struct.Struct("<8sHH11I40s")
V4_CHUNK_HEADER_STRUCT = struct.Struct("<BBHIQ")
V4_ECG_STRUCT = struct.Struct("<I4iHHBBBB")
V4_MIC_STRUCT = struct.Struct("<HH8h")
V4_IMU_STRUCT = struct.Struct("<6hB3x")
V4_GAP_STRUCT = struct.Struct("<BBHQII")
V4_SESSION_DIAGNOSTICS_STRUCT = struct.Struct("<HHB3xIII4H11I" + ("IIQQ" * 3))
TRAILER_STRUCT_V4 = struct.Struct("<8sHHIQII15Q")

QUALITY_NAMES = {0: "unverified", 1: "complete", 2: "minor_loss", 3: "failed"}
V4_STREAM_NAMES = {1: "ECG", 2: "MIC", 3: "IMU"}
V4_STREAM_PERIOD_US = {1: 2000, 2: 500, 3: 8000}


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
class BinaryLogTrailerV4:
    chunk_count: int
    elapsed_us: int
    payload_crc32: int
    ecg_config_flags: int
    ecg_frames_received: int
    ecg_invalid_frames: int
    ecg_acquisition_overruns: int
    ecg_late_frames: int
    ecg_saturation_events: int
    ecg_lead_off_events: int
    ecg_register_readback_mismatches: int
    mic_samples_acquired: int
    mic_samples_persisted: int
    mic_explicit_gap_samples: int
    mic_frame_queue_drops: int
    imu_samples: int
    imu_missed_updates: int
    imu_poll_failures: int
    sd_dropped_chunks: int


@dataclass(frozen=True)
class SessionDiagnosticsV4:
    schema_version: int
    quality: str
    core1_max_stall_us: int
    core1_max_busy_us: int
    sd_max_write_us: int
    ecg_queue_high_water: int
    mic_queue_high_water: int
    imu_queue_high_water: int
    storage_operations_rejected: int
    start_ack_us: int
    stop_ack_us: int
    discarded_pre_session_ecg: int
    discarded_pre_session_mic: int
    discarded_pre_session_imu: int
    ecg_queue_dropped: int
    mic_queue_dropped: int
    imu_queue_dropped: int
    sd_write_failures: int
    ecg_first_sequence: int
    ecg_last_sequence: int
    ecg_first_us: int
    ecg_last_us: int
    mic_first_sequence: int
    mic_last_sequence: int
    mic_first_us: int
    mic_last_us: int
    imu_first_sequence: int
    imu_last_sequence: int
    imu_first_us: int
    imu_last_us: int


@dataclass(frozen=True)
class BinaryLogInfo:
    header: BinaryLogHeader
    record_count: int
    complete: bool
    crc_valid: bool | None
    trailer: BinaryLogTrailer | BinaryLogTrailerV4 | None
    trailing_bytes: int
    status: str
    v4_gap_samples: tuple[int, int, int] = (0, 0, 0)
    session_diagnostics: SessionDiagnosticsV4 | None = None
    quality: str = "unverified"
    quality_reason: str = "recording has not been verified"


def timing_warning(info: BinaryLogInfo) -> str | None:
    """Explain when a log must not be used for precise cross-sensor timing."""
    if info.quality == "failed":
        return f"Do not use for analysis: recording quality FAILED ({info.quality_reason})."
    if info.quality == "unverified":
        return f"Do not use for precise timing: recording is UNVERIFIED ({info.quality_reason})."
    if isinstance(info.trailer, BinaryLogTrailerV4):
        if info.v4_gap_samples[0]:
            return (
                "Do not use for precise timing: the recording contains "
                f"{info.v4_gap_samples[0]} explicit missing ECG samples."
            )
        if info.v4_gap_samples[2]:
            return (
                "Do not use for precise ECG-to-IMU timing: the recording contains "
                f"{info.v4_gap_samples[2]} explicit missing IMU samples."
            )
        if info.trailer.mic_explicit_gap_samples:
            return (
                "Do not use for precise ECG-to-microphone timing: the recording contains "
                f"{info.trailer.mic_explicit_gap_samples} explicit missing microphone samples."
            )
        if info.trailer.mic_samples_acquired != info.trailer.mic_samples_persisted:
            return "Do not use for precise ECG-to-microphone timing: microphone accounting does not reconcile."
    return None


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

    if format_version == 4:
        if record_size != 0:
            raise ValueError(f"Bad record size: format v4 requires 0, got {record_size}")
    else:
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


def _v4_chunk_count(handle: BinaryIO, offset: int, size: int) -> tuple[int, int]:
    """Return complete v4 chunks and bytes left after the final complete chunk."""
    handle.seek(offset)
    remaining = size
    count = 0
    while remaining >= V4_CHUNK_HEADER_STRUCT.size:
        raw_header = handle.read(V4_CHUNK_HEADER_STRUCT.size)
        if len(raw_header) != V4_CHUNK_HEADER_STRUCT.size:
            break
        _, _, payload_size, _, _ = V4_CHUNK_HEADER_STRUCT.unpack(raw_header)
        remaining -= V4_CHUNK_HEADER_STRUCT.size
        if payload_size > remaining:
            return count, remaining + V4_CHUNK_HEADER_STRUCT.size
        handle.seek(payload_size, 1)
        remaining -= payload_size
        count += 1
    return count, remaining


def _parse_v4_session_diagnostics(payload: bytes) -> SessionDiagnosticsV4 | None:
    if len(payload) != V4_SESSION_DIAGNOSTICS_STRUCT.size:
        return None
    values = V4_SESSION_DIAGNOSTICS_STRUCT.unpack(payload)
    if values[0] != 1 or values[1] != V4_SESSION_DIAGNOSTICS_STRUCT.size:
        return None
    return SessionDiagnosticsV4(
        schema_version=values[0],
        quality=QUALITY_NAMES.get(values[2], f"unknown_{values[2]}"),
        core1_max_stall_us=values[3],
        core1_max_busy_us=values[4],
        sd_max_write_us=values[5],
        ecg_queue_high_water=values[6],
        mic_queue_high_water=values[7],
        imu_queue_high_water=values[8],
        storage_operations_rejected=values[10],
        start_ack_us=values[11],
        stop_ack_us=values[12],
        discarded_pre_session_ecg=values[13],
        discarded_pre_session_mic=values[14],
        discarded_pre_session_imu=values[15],
        ecg_queue_dropped=values[16],
        mic_queue_dropped=values[17],
        imu_queue_dropped=values[18],
        sd_write_failures=values[19],
        ecg_first_sequence=values[21],
        ecg_last_sequence=values[22],
        ecg_first_us=values[23],
        ecg_last_us=values[24],
        mic_first_sequence=values[25],
        mic_last_sequence=values[26],
        mic_first_us=values[27],
        mic_last_us=values[28],
        imu_first_sequence=values[29],
        imu_last_sequence=values[30],
        imu_first_us=values[31],
        imu_last_us=values[32],
    )


def _v4_metadata(
    handle: BinaryIO, offset: int, size: int
) -> tuple[tuple[int, int, int], SessionDiagnosticsV4 | None]:
    """Return explicit loss totals and the final valid session diagnostics chunk."""
    handle.seek(offset)
    remaining = size
    totals = [0, 0, 0]
    diagnostics = None
    while remaining >= V4_CHUNK_HEADER_STRUCT.size:
        raw_header = handle.read(V4_CHUNK_HEADER_STRUCT.size)
        if len(raw_header) != V4_CHUNK_HEADER_STRUCT.size:
            break
        chunk_type, _flags, payload_size, _sequence, _session_us = V4_CHUNK_HEADER_STRUCT.unpack(raw_header)
        remaining -= V4_CHUNK_HEADER_STRUCT.size
        if payload_size > remaining:
            break
        payload = handle.read(payload_size)
        remaining -= payload_size
        if chunk_type == 4 and payload_size == V4_GAP_STRUCT.size:
            stream, _reason, _reserved, missing, _expected, _next = V4_GAP_STRUCT.unpack(payload)
            if 1 <= stream <= 3:
                totals[stream - 1] += missing
        elif chunk_type == 5:
            parsed = _parse_v4_session_diagnostics(payload)
            if parsed is not None:
                diagnostics = parsed
    return tuple(totals), diagnostics


def _loss_ppm(missing: int, persisted: int) -> int:
    total = missing + persisted
    return 0 if missing == 0 or total == 0 else min(1_000_000, missing * 1_000_000 // total)


def _v4_quality(
    complete: bool,
    crc_valid: bool | None,
    trailer: BinaryLogTrailerV4 | None,
    gaps: tuple[int, int, int],
    diagnostics: SessionDiagnosticsV4 | None,
) -> tuple[str, str]:
    if not complete:
        if trailer is not None or crc_valid is False:
            return "failed", "trailer, CRC, or chunk-count verification failed"
        return "unverified", "clean-stop trailer is missing"
    if trailer is None:
        return "unverified", "clean-stop trailer is missing"

    mic_accounting_mismatch = (
        trailer.mic_samples_acquired
        != trailer.mic_samples_persisted + trailer.mic_explicit_gap_samples
    )
    excessive_loss = (
        _loss_ppm(gaps[0], trailer.ecg_frames_received) >= 10_000
        or _loss_ppm(gaps[1], trailer.mic_samples_persisted) >= 10_000
        or _loss_ppm(gaps[2], trailer.imu_samples) >= 10_000
    )
    hard_failures = trailer.sd_dropped_chunks != 0 or mic_accounting_mismatch or excessive_loss
    if diagnostics is not None:
        hard_failures = hard_failures or diagnostics.sd_write_failures != 0
    if hard_failures:
        reasons = []
        if trailer.sd_dropped_chunks:
            reasons.append("SD chunks dropped")
        if mic_accounting_mismatch:
            reasons.append("microphone accounting mismatch")
        if excessive_loss:
            reasons.append("explicit stream loss is at least 1 percent")
        if diagnostics is not None and diagnostics.sd_write_failures:
            reasons.append("SD write failure")
        return "failed", ", ".join(reasons)

    warning = (
        any(gaps)
        or trailer.ecg_invalid_frames != 0
        or trailer.ecg_acquisition_overruns != 0
        or trailer.ecg_saturation_events != 0
        or trailer.ecg_lead_off_events != 0
        or trailer.ecg_register_readback_mismatches != 0
        or trailer.mic_frame_queue_drops != 0
        or trailer.imu_missed_updates != 0
        or trailer.imu_poll_failures != 0
    )
    if diagnostics is not None:
        if diagnostics.quality == "failed":
            return "failed", "device session diagnostics reported failure"
        warning = warning or diagnostics.quality == "minor_loss" or any((
            diagnostics.ecg_queue_dropped,
            diagnostics.mic_queue_dropped,
            diagnostics.imu_queue_dropped,
        ))
    if warning:
        return "minor_loss", "structure verified, but acquisition warnings or explicit gaps exist"
    return "complete", "trailer, CRC, stream accounting, and diagnostics verified"


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

    if header.format_version == 4 and payload_size >= TRAILER_STRUCT_V4.size:
        handle.seek(file_size - TRAILER_STRUCT_V4.size)
        raw_trailer = handle.read(TRAILER_STRUCT_V4.size)
        unpacked = TRAILER_STRUCT_V4.unpack(raw_trailer)
        magic, trailer_size, trailer_version, chunk_count, elapsed_us, payload_crc32, ecg_config_flags, *counters = unpacked
        if magic == TRAILER_MAGIC_V4:
            data_size = payload_size - TRAILER_STRUCT_V4.size
            if trailer_size != TRAILER_STRUCT_V4.size or trailer_version != 4:
                status = "incomplete: invalid v4 trailer header"
            else:
                trailer = BinaryLogTrailerV4(
                    chunk_count=chunk_count,
                    elapsed_us=elapsed_us,
                    payload_crc32=payload_crc32,
                    ecg_config_flags=ecg_config_flags,
                    ecg_frames_received=counters[0],
                    ecg_invalid_frames=counters[1],
                    ecg_acquisition_overruns=counters[2],
                    ecg_late_frames=counters[3],
                    ecg_saturation_events=counters[4],
                    ecg_lead_off_events=counters[5],
                    ecg_register_readback_mismatches=counters[6],
                    mic_samples_acquired=counters[7],
                    mic_samples_persisted=counters[8],
                    mic_explicit_gap_samples=counters[9],
                    mic_frame_queue_drops=counters[10],
                    imu_samples=counters[11],
                    imu_missed_updates=counters[12],
                    imu_poll_failures=counters[13],
                    sd_dropped_chunks=counters[14],
                )
                calculated_crc = _stream_crc32(handle, header.header_size, data_size)
                crc_valid = calculated_crc == trailer.payload_crc32
                parsed_chunks, trailing_bytes = _v4_chunk_count(handle, header.header_size, data_size)
                complete = crc_valid and trailing_bytes == 0 and parsed_chunks == trailer.chunk_count
                if complete:
                    status = "complete: clean stop trailer and payload CRC verified"
                elif not crc_valid:
                    status = "incomplete: v4 payload CRC mismatch"
                elif trailing_bytes:
                    status = "incomplete: bytes remain before v4 trailer"
                else:
                    status = "incomplete: v4 trailer chunk count mismatch"

    gap_samples = (0, 0, 0)
    session_diagnostics = None
    if header.format_version == 4:
        record_count, trailing_bytes = _v4_chunk_count(handle, header.header_size, data_size)
        gap_samples, session_diagnostics = _v4_metadata(handle, header.header_size, data_size)
    else:
        record_count, trailing_bytes = divmod(data_size, header.record_size)

    quality = "complete" if complete else "unverified"
    quality_reason = status
    if header.format_version == 4:
        quality, quality_reason = _v4_quality(
            complete,
            crc_valid,
            trailer if isinstance(trailer, BinaryLogTrailerV4) else None,
            gap_samples,
            session_diagnostics,
        )

    return BinaryLogInfo(
        header=header,
        record_count=record_count,
        complete=complete,
        crc_valid=crc_valid,
        trailer=trailer,
        trailing_bytes=trailing_bytes,
        status=status,
        v4_gap_samples=gap_samples,
        session_diagnostics=session_diagnostics,
        quality=quality,
        quality_reason=quality_reason,
    )


def inspect_file(source: Path) -> BinaryLogInfo:
    with source.open("rb") as handle:
        header = read_header(handle)
        return inspect_handle(handle, header)


def _v4_row(stream: str, session_us: int, sequence: int, valid: int = 1, **values: str) -> list[str]:
    row = ["LOG", stream, str(session_us), str(sequence), str(valid)]
    row.extend(str(values.get(key, "")) for key in V4_VALUE_KEYS)
    row.append("4")
    return row


def _diagnostic_values(diagnostics: SessionDiagnosticsV4) -> dict[str, str]:
    return {
        "session_quality": diagnostics.quality,
        "diagnostics_schema": str(diagnostics.schema_version),
        "core1_max_stall_us": str(diagnostics.core1_max_stall_us),
        "core1_max_busy_us": str(diagnostics.core1_max_busy_us),
        "sd_max_write_us": str(diagnostics.sd_max_write_us),
        "ecg_queue_high_water": str(diagnostics.ecg_queue_high_water),
        "mic_queue_high_water": str(diagnostics.mic_queue_high_water),
        "imu_queue_high_water": str(diagnostics.imu_queue_high_water),
        "storage_operations_rejected": str(diagnostics.storage_operations_rejected),
        "start_ack_us": str(diagnostics.start_ack_us),
        "stop_ack_us": str(diagnostics.stop_ack_us),
        "discarded_pre_session_ecg": str(diagnostics.discarded_pre_session_ecg),
        "discarded_pre_session_mic": str(diagnostics.discarded_pre_session_mic),
        "discarded_pre_session_imu": str(diagnostics.discarded_pre_session_imu),
        "ecg_queue_dropped": str(diagnostics.ecg_queue_dropped),
        "mic_queue_dropped": str(diagnostics.mic_queue_dropped),
        "imu_queue_dropped": str(diagnostics.imu_queue_dropped),
        "sd_write_failures": str(diagnostics.sd_write_failures),
        "ecg_first_sequence": str(diagnostics.ecg_first_sequence),
        "ecg_last_sequence": str(diagnostics.ecg_last_sequence),
        "ecg_first_us": str(diagnostics.ecg_first_us),
        "ecg_last_us": str(diagnostics.ecg_last_us),
        "mic_first_sequence": str(diagnostics.mic_first_sequence),
        "mic_last_sequence": str(diagnostics.mic_last_sequence),
        "mic_first_us": str(diagnostics.mic_first_us),
        "mic_last_us": str(diagnostics.mic_last_us),
        "imu_first_sequence": str(diagnostics.imu_first_sequence),
        "imu_last_sequence": str(diagnostics.imu_last_sequence),
        "imu_first_us": str(diagnostics.imu_first_us),
        "imu_last_us": str(diagnostics.imu_last_us),
    }


def _iter_v4_csv_rows(handle: BinaryIO, header: BinaryLogHeader, info: BinaryLogInfo) -> Iterable[list[str]]:
    handle.seek(header.header_size)
    end = header.header_size
    if info.trailer is not None:
        end_handle = handle.seek(0, 2)
        end = end_handle - TRAILER_STRUCT_V4.size
        handle.seek(header.header_size)

    while handle.tell() < end:
        raw_header = handle.read(V4_CHUNK_HEADER_STRUCT.size)
        if len(raw_header) != V4_CHUNK_HEADER_STRUCT.size:
            break
        chunk_type, flags, payload_size, sequence, session_us = V4_CHUNK_HEADER_STRUCT.unpack(raw_header)
        payload = handle.read(payload_size)
        if len(payload) != payload_size:
            break

        if chunk_type == 1 and payload_size == V4_ECG_STRUCT.size:
            status, ch1, ch2, ch3, ch4, diag, delay, lead_p, lead_n, saturation, _ = V4_ECG_STRUCT.unpack(payload)
            valid = bool(flags & 1) and (status & 0xF00000) == 0xC00000 and not (diag & 0x0040)
            sample_values = [str(ch1), str(ch2), str(ch3), str(ch4)] if valid else ["NaN"] * 4
            yield _v4_row(
                "ECG", session_us, sequence, int(valid), session_quality=info.quality,
                ecg_status=f"{status:06X}", ecg_ch1_raw=sample_values[0],
                ecg_ch2_raw=sample_values[1], ecg_ch3_raw=sample_values[2],
                ecg_ch4_raw=sample_values[3], lead_i=sample_values[0],
                lead_ii=sample_values[1],
                lead_iii_derived=str(ch2 - ch1) if valid else "NaN",
                lead_off_p=f"{lead_p:02X}",
                lead_off_n=f"{lead_n:02X}", sat_mask=f"{saturation:02X}",
                diag_flags=f"{diag:04X}", frame_read_delay_us=str(delay),
            )
        elif chunk_type == 2 and payload_size == V4_MIC_STRUCT.size:
            sample_count, _reserved, *samples = V4_MIC_STRUCT.unpack(payload)
            sample_count = min(sample_count, len(samples))
            valid = bool(flags & 1)
            for sample_index, sample in enumerate(samples[:sample_count]):
                yield _v4_row(
                    "MIC", session_us + sample_index * 500, sequence + sample_index, int(valid),
                    mic_block_sample_count=str(sample_count),
                    mic_block_sample_index=str(sample_index),
                    mic_sample=str(sample) if valid else "NaN",
                    session_quality=info.quality,
                )
        elif chunk_type == 3 and payload_size == V4_IMU_STRUCT.size:
            x_mg, y_mg, z_mg, raw_x, raw_y, raw_z, diag = V4_IMU_STRUCT.unpack(payload)
            valid = bool(flags & 1)
            yield _v4_row(
                "IMU", session_us, sequence, int(valid), session_quality=info.quality,
                imu_x_g=f"{x_mg / 1000.0:.4f}" if valid else "NaN",
                imu_y_g=f"{y_mg / 1000.0:.4f}" if valid else "NaN",
                imu_z_g=f"{z_mg / 1000.0:.4f}" if valid else "NaN",
                raw_x=str(raw_x) if valid else "NaN", raw_y=str(raw_y) if valid else "NaN",
                raw_z=str(raw_z) if valid else "NaN", imu_diag_flags=f"{diag:02X}",
            )
        elif chunk_type == 4 and payload_size == V4_GAP_STRUCT.size:
            stream, reason, _reserved, missing, expected, next_sequence = V4_GAP_STRUCT.unpack(payload)
            stream_name = V4_STREAM_NAMES.get(stream, f"UNKNOWN_{stream}")
            yield _v4_row(
                "GAP", session_us, sequence, 0, session_quality=info.quality,
                gap_stream=stream_name, gap_reason=str(reason),
                gap_missing_samples=str(missing), gap_expected_sequence=str(expected),
                gap_next_sequence=str(next_sequence),
            )
            period_us = V4_STREAM_PERIOD_US.get(stream)
            if period_us is not None:
                for missing_index in range(missing):
                    yield _v4_row(
                        f"{stream_name}_MISSING",
                        session_us + missing_index * period_us,
                        (expected + missing_index) & 0xFFFFFFFF,
                        0,
                        session_quality=info.quality,
                        gap_stream=stream_name,
                        gap_reason=str(reason),
                        gap_missing_samples=str(missing),
                        gap_expected_sequence=str(expected),
                        gap_next_sequence=str(next_sequence),
                        missing_index=str(missing_index),
                    )
        elif chunk_type == 5:
            diagnostics = _parse_v4_session_diagnostics(payload)
            if diagnostics is None:
                yield _v4_row("SESSION_DIAGNOSTICS_INVALID", session_us, sequence, 0,
                              session_quality=info.quality)
            else:
                yield _v4_row("SESSION_DIAGNOSTICS", session_us, sequence, 1,
                              **_diagnostic_values(diagnostics))
        else:
            yield _v4_row("UNKNOWN", session_us, sequence, 0, session_quality=info.quality)


def iter_csv_rows(handle: BinaryIO) -> Iterable[list[str]]:
    header = read_header(handle)
    info = inspect_handle(handle, header)
    if header.format_version == 4:
        yield from _iter_v4_csv_rows(handle, header, info)
        return
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

        ecg_valid = (ecg_status & 0xF00000) == 0xC00000 and not (diag_flags & 0x0040)
        ecg_values = [str(lead_i), str(lead_ii), str(lead_iii)] if ecg_valid else ["NaN"] * 3
        yield [
            "LOG",
            str(elapsed_ms),
            str(ecg_us),
            str(ecg_seq8),
            str(ecg_seq),
            f"{ecg_status:06X}",
            str(int(ecg_valid)),
            ecg_values[0],
            ecg_values[1],
            ecg_values[2],
            "",
            ecg_values[0],
            ecg_values[1],
            str(lead_ii - lead_i) if ecg_valid else "NaN",
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
        header = read_header(src)
        writer.writerow(CSV_HEADER_V4 if header.format_version == 4 else CSV_HEADER)
        src.seek(0)
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
    warning = timing_warning(info)
    if warning:
        print(f"Timing warning: {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
