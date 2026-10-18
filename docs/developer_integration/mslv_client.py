"""Read-only MotemaSens MSLV v1/v2 example; Python standard library only.

Windows: py mslv_client.py --base http://192.168.1.50 --seconds 10
Offline verification: py mslv_client.py --self-test
Does not start SD recording or change device configuration.
"""
import argparse
import json
import struct
import time
import urllib.parse
import urllib.request

HEADER = struct.Struct('<4sBBHII8H')
ECG_V1 = struct.Struct('<IIiHBB')
ECG_V2 = struct.Struct('<IIiHBBii')
MIC = struct.Struct('<IIhBB')
IMU = struct.Struct('<IIhhhBB')


def decode(data):
    if len(data) < HEADER.size:
        raise ValueError('Truncated header')
    magic, version, flags, size, server_us, seq, ec, mc, ic, _, er, mr, ir, _ = HEADER.unpack_from(data)
    if magic != b'MSLV' or version not in (1, 2) or size < 32:
        raise ValueError('Unsupported MSLV header')
    ecg_struct = ECG_V2 if version == 2 else ECG_V1
    expected = size + ec * ecg_struct.size + mc * MIC.size + ic * IMU.size
    if len(data) != expected:
        raise ValueError('Packet length/count mismatch')
    result = dict(version=version, flags=flags, server_us=server_us,
                  packet_sequence=seq, rates=[er, mr, ir])
    offset = size
    for name, count, record in [('ecg', ec, ecg_struct), ('mic', mc, MIC), ('imu', ic, IMU)]:
        points = []
        for _ in range(count):
            points.append(record.unpack_from(data, offset))
            offset += record.size
        result[name] = points
    return result


def read_exact(response, count):
    result = bytearray()
    while len(result) < count:
        block = response.read(count - len(result))
        if not block:
            raise EOFError('Device closed stream')
        result.extend(block)
    return bytes(result)


def framed_packet(response):
    length = struct.unpack('<I', read_exact(response, 4))[0]
    if not 32 <= length <= 16384:
        raise ValueError('Unsafe frame length')
    return decode(read_exact(response, length))


def stream(base, seconds):
    url = urllib.parse.urlsplit(base)
    if url.scheme != 'http' or not url.hostname:
        raise ValueError('Use the Local HTTP device address')
    cursors = dict(ecgAfter=0, micAfter=0, imuAfter=0)
    query = urllib.parse.urlencode(cursors)
    with urllib.request.urlopen(base.rstrip('/') + '/api/live?' + query, timeout=5) as response:
        primer_bytes = response.read(16385)
        if len(primer_bytes) > 16384:
            raise ValueError('Primer too large')
        primer = decode(primer_bytes)
    for stream_name in ('ecg', 'mic', 'imu'):
        if primer[stream_name]:
            cursors[stream_name + 'After'] = primer[stream_name][-1][0]
    endpoint = base.rstrip('/') + '/api/live-stream?' + urllib.parse.urlencode(cursors)
    counts = dict(ecg=len(primer['ecg']), mic=len(primer['mic']), imu=len(primer['imu']))
    start = time.monotonic()
    with urllib.request.urlopen(endpoint, timeout=10) as response:
        if response.status != 200:
            raise ValueError(f'HTTP {response.status}')
        while time.monotonic() - start < seconds:
            packet = framed_packet(response)
            for name in counts:
                counts[name] += len(packet[name])
            # Each tuple's first fields are sequence and timestamp. Inspect
            # validity/saturation before using values; no filtering is applied.
    print(json.dumps(dict(seconds=round(time.monotonic()-start, 3), samples_received=counts)))


def self_test():
    import io
    for version, record in [(1, ECG_V1), (2, ECG_V2)]:
        values = (0xffffffff, 0xfffffffe, -3500, 48, 1, 0)
        if version == 2:
            values += (-1000, 2500)
        data = HEADER.pack(b'MSLV', version, 7, 32, 5, 1, 1, 1, 1, 0, 500, 2000, 125, 0)
        data += record.pack(*values) + MIC.pack(1, 5, -32768, 1, 0) + IMU.pack(1, 6, -1000, 0, 1000, 0, 1)
        framed = struct.pack('<I', len(data)) + data
        class Fragmented(io.BytesIO):
            def read(self, count=-1):
                return super().read(min(count, 3))
        source = Fragmented(framed + framed)
        for _ in range(2):
            packet = framed_packet(source)
            assert packet['ecg'][0][2] == -3500
            assert packet['mic'][0][2] == -32768
            assert packet['imu'][0][2] == -1000
            if version == 2:
                assert packet['ecg'][0][7] - packet['ecg'][0][6] == 3500
        try:
            decode(data[:-1])
        except ValueError:
            pass
        else:
            raise AssertionError('Accepted truncated data')
    try:
        framed_packet(io.BytesIO(struct.pack('<I', 0xffffffff)))
    except ValueError:
        pass
    else:
        raise AssertionError('Accepted excessive allocation')
    print('PASS: v1/v2, signed values, Lead III, fragmented/coalesced reads, malformed lengths')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base')
    parser.add_argument('--seconds', type=float, default=10)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.base and 0 < args.seconds <= 3600:
        stream(args.base, args.seconds)
    else:
        parser.error('Provide --self-test or --base and a duration in (0, 3600]')
