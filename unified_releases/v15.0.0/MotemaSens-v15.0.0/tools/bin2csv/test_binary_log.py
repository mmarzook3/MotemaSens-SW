from __future__ import annotations

import csv
import struct
import tempfile
import zlib
from pathlib import Path

from binary_log import (
    HEADER_STRUCT,
    MAGIC,
    RECORD_STRUCT,
    RECORD_STRUCT_V2,
    RECORD_STRUCT_V3,
    TRAILER_MAGIC_V3,
    TRAILER_STRUCT_V3,
    convert_file,
    inspect_file,
    read_header,
)


def make_sample(path: Path) -> None:
    header = HEADER_STRUCT.pack(
        MAGIC,
        HEADER_STRUCT.size,
        RECORD_STRUCT.size,
        1,
        1234,
        0x07,
        b"\x00\x00\x00",
        b"test-fw".ljust(40, b"\x00"),
    )
    records = [
        RECORD_STRUCT.pack(
            10,
            1000,
            1,
            0xC00000,
            -100,
            200,
            300,
            20,
            30,
            3277,
            6553,
            101,
            -202,
            303,
            10,
            -20,
            30,
            0x0034,
            1,
            0,
            0,
            0,
            2,
            3,
            0,
        ),
        RECORD_STRUCT.pack(
            12,
            2000,
            2,
            0xC00000,
            -110,
            210,
            320,
            22,
            32,
            -3277,
            9830,
            102,
            -203,
            304,
            11,
            -21,
            31,
            0x0034,
            2,
            0,
            0,
            0,
            4,
            5,
            0,
        ),
    ]
    path.write_bytes(header + b"".join(records))


def make_v2_sample(path: Path) -> None:
    header = HEADER_STRUCT.pack(
        MAGIC,
        HEADER_STRUCT.size,
        RECORD_STRUCT_V2.size,
        2,
        1234,
        0x07,
        b"\x00\x00\x00",
        b"v6.0.0".ljust(40, b"\x00"),
    )
    record = RECORD_STRUCT_V2.pack(
        10, 1000, 1, 0xC00000, -100, 200, 300, 20, 30,
        3277, 6553, 101, -202, 303, 10, -20, 30, 0x0034,
        1, 0, 0, 0, 2, 3, 0,
        900, 44, -32767, -16384, 16384, 32767,
    )
    path.write_bytes(header + record)


def make_v3_sample(path: Path, include_trailer: bool = True) -> None:
    header = HEADER_STRUCT.pack(
        MAGIC,
        HEADER_STRUCT.size,
        RECORD_STRUCT_V3.size,
        3,
        1234,
        0x07,
        b"\x00\x00\x00",
        b"phase1-v3".ljust(40, b"\x00"),
    )
    record = RECORD_STRUCT_V3.pack(
        10, 1000, 0xFFFFFFFE, 0xC00000, -100, 200, 300, 20, 30,
        3277, 6553, 101, -202, 303, 10, -20, 30, 0x0034,
        1, 0, 0, 0, 2, 3, 0,
        900, 0xFFFFFFFC, -32767, -16384, 16384, 32767,
        0x05, 2, 3, 1, 42, 0xFFFFFFFD,
    )
    if not include_trailer:
        path.write_bytes(header + record)
        return
    trailer = TRAILER_STRUCT_V3.pack(
        TRAILER_MAGIC_V3,
        TRAILER_STRUCT_V3.size,
        3,
        1, 10, zlib.crc32(record) & 0xFFFFFFFF,
        1, 2, 3, 4, 5, 6, 7, 8,
        struct.pack("<10I", 9, 10, 11, 12, 13, 14, 15, 0x07, 16, 17),
    )
    path.write_bytes(header + record + trailer)


def main() -> int:
    with tempfile.TemporaryDirectory() as temp:
        source = Path(temp) / "sample.bin"
        destination = Path(temp) / "sample.csv"
        make_sample(source)
        rows = convert_file(source, destination, overwrite=True)
        assert rows == 2
        with destination.open(newline="", encoding="utf-8") as handle:
            csv_rows = list(csv.DictReader(handle))
        assert csv_rows[0]["LOG_HEADER"] == "LOG"
        assert csv_rows[0]["ecg_status"] == "C00000"
        assert csv_rows[0]["ecg_valid"] == "1"
        assert csv_rows[0]["ecg_ch1_raw"] == "-100"
        assert csv_rows[0]["ecg_ch3_raw"] == "300"
        assert csv_rows[0]["lead_iii_derived"] == "300"
        assert csv_rows[0]["mic_trace"] == "0.1000"
        assert csv_rows[0]["acc_x_g"] == "0.1010"

        v2_source = Path(temp) / "sample-v2.bin"
        v2_destination = Path(temp) / "sample-v2.csv"
        make_v2_sample(v2_source)
        rows = convert_file(v2_source, v2_destination, overwrite=True)
        assert rows == 1
        with v2_destination.open(newline="", encoding="utf-8") as handle:
            v2_rows = list(csv.DictReader(handle))
        assert v2_rows[0]["mic_first_us"] == "900"
        assert v2_rows[0]["mic_sample_seq"] == "44"
        assert [v2_rows[0][f"mic_raw_{index}"] for index in range(4)] == [
            "-1.0000", "-0.5000", "0.5000", "1.0000"
        ]

        mismatched_v1 = Path(temp) / "mismatched-v1.bin"
        mismatched_v1.write_bytes(
            HEADER_STRUCT.pack(
                MAGIC, HEADER_STRUCT.size, RECORD_STRUCT_V2.size, 1, 0, 0x07,
                b"\x00\x00\x00", b"test-fw".ljust(40, b"\x00"),
            )
        )
        try:
            with mismatched_v1.open("rb") as handle:
                read_header(handle)
            raise AssertionError("v1 header with v2 record size was accepted")
        except ValueError as error:
            assert "Bad record size" in str(error)

        v3_source = Path(temp) / "sample-v3.bin"
        v3_destination = Path(temp) / "sample-v3.csv"
        make_v3_sample(v3_source)
        info = inspect_file(v3_source)
        assert info.complete is True
        assert info.crc_valid is True
        assert info.trailer is not None
        assert info.trailer.mic_log_underflows == 5
        assert info.trailer.mic_source_gap_samples == 9
        assert info.trailer.ecg_frames_received == 10
        assert info.trailer.ecg_saturation_events == 11
        assert info.trailer.ecg_lead_off_events == 12
        assert info.trailer.ecg_cable_noise_events == 13
        assert info.trailer.ecg_rld_unstable_events == 14
        assert info.trailer.ecg_register_readback_mismatches == 15
        assert info.trailer.ecg_config_flags == 0x07
        assert info.trailer.imu_missed_updates == 16
        assert info.trailer.imu_poll_failures == 17
        rows = convert_file(v3_source, v3_destination, overwrite=True)
        assert rows == 1
        with v3_destination.open(newline="", encoding="utf-8") as handle:
            v3_rows = list(csv.reader(handle))
        assert v3_rows[0][-7:] == [
            "mic_block_valid_mask", "mic_missing_count", "mic_block_reason",
            "imu_valid", "imu_age_us", "imu_sample_seq", "log_format_version",
        ]
        assert v3_rows[1][-7:] == ["05", "2", "queue_underflow", "1", "42", "4294967293", "3"]

        truncated_v3 = Path(temp) / "sample-v3-truncated.bin"
        make_v3_sample(truncated_v3, include_trailer=False)
        truncated_info = inspect_file(truncated_v3)
        assert truncated_info.complete is False
        assert truncated_info.record_count == 1
        assert "trailer missing" in truncated_info.status

        corrupted_v3 = Path(temp) / "sample-v3-corrupted.bin"
        corrupted = bytearray(v3_source.read_bytes())
        corrupted[HEADER_STRUCT.size + 16] ^= 0x01
        corrupted_v3.write_bytes(corrupted)
        corrupted_info = inspect_file(corrupted_v3)
        assert corrupted_info.complete is False
        assert corrupted_info.crc_valid is False
        assert "CRC mismatch" in corrupted_info.status

        bad_trailer_v3 = Path(temp) / "sample-v3-bad-trailer.bin"
        bad_trailer = bytearray(v3_source.read_bytes())
        bad_trailer[HEADER_STRUCT.size + RECORD_STRUCT_V3.size + 8] = 1
        bad_trailer_v3.write_bytes(bad_trailer)
        bad_trailer_info = inspect_file(bad_trailer_v3)
        assert bad_trailer_info.complete is False
        assert bad_trailer_info.record_count == 1
        assert "invalid v3 trailer header" in bad_trailer_info.status

        mismatched_v2 = Path(temp) / "mismatched-v2.bin"
        mismatched_v2.write_bytes(
            HEADER_STRUCT.pack(
                MAGIC, HEADER_STRUCT.size, RECORD_STRUCT.size, 2, 0, 0x07,
                b"\x00\x00\x00", b"test-fw".ljust(40, b"\x00"),
            )
        )
        try:
            with mismatched_v2.open("rb") as handle:
                read_header(handle)
            raise AssertionError("v2 header with v1 record size was accepted")
        except ValueError as error:
            assert "Bad record size" in str(error)
    print("binary_log self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
