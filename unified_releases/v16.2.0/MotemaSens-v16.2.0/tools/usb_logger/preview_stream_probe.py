"""Read-only Local WiFi MSLV probe. Does not start/stop recording.
Usage: python preview_stream_probe.py --base-url http://DEVICE_IP --duration 30 --output preview.json
Records counters/timing only, no physiological samples or credentials.
"""
import argparse
import json
import statistics
import struct
import time
import urllib.request
from pathlib import Path

HEADER = struct.Struct('<4sBBHII8H')

def status(base):
    with urllib.request.urlopen(base+'/api/status', timeout=10) as response:
        data=json.load(response)
    keys=('deviceId','version','uptime_ms','ecg_sample_rate_hz','mic_sample_rate_hz',
          'imu_sample_rate_hz','ecg_queue_dropped','mic_frame_queue_dropped',
          'imu_queue_dropped','ecg_acquisition_overruns','ecg_invalid_frames',
          'ecg_frame_read_late','system_diagnostics')
    return {key:data[key] for key in keys if key in data}

def exact(response, count):
    result=bytearray()
    while len(result)<count:
        block=response.read(count-len(result))
        if not block: raise EOFError('Live stream closed')
        result.extend(block)
    return result

def run(base, duration):
    before=status(base)
    counts=[0,0,0]; gaps=[0,0,0]; duplicates=[0,0,0]; invalid=[0,0,0]
    previous=[None,None,None]; first_time=[None,None,None]; last_time=[0,0,0]
    timestamp_span=[0,0,0]; intervals=[]; cursor_gaps=0; packets=0
    started=time.monotonic(); last_packet=None; rates=[]; error=None
    try:
        with urllib.request.urlopen(base+'/api/live-stream?ecgAfter=0&micAfter=0&imuAfter=0',timeout=10) as response:
            while time.monotonic()-started<duration:
                length=struct.unpack('<I',exact(response,4))[0]
                if not 32<=length<=16384: raise ValueError('Invalid frame length')
                data=exact(response,length)
                h=HEADER.unpack_from(data)
                if h[0]!=b'MSLV' or h[1] not in (1,2) or h[3]<32: raise ValueError('Invalid MSLV header')
                sizes=[24 if h[1]==2 else 16,12,16]
                if h[3]+sum(h[6+s]*sizes[s] for s in range(3))!=length: raise ValueError('Invalid packet sizes')
                arrived=time.monotonic()
                if last_packet is not None: intervals.append((arrived-last_packet)*1000)
                last_packet=arrived; packets+=1; rates=list(h[10:13])
                cursor_gaps+=bool(h[2]&0x70)
                offset=h[3]
                for s in range(3):
                    for _ in range(h[6+s]):
                        sequence,timestamp=struct.unpack_from('<II',data,offset)
                        if previous[s] is not None:
                            delta=(sequence-previous[s])&0xffffffff
                            if delta==0 or delta>=0x80000000: duplicates[s]+=1
                            else: gaps[s]+=delta-1
                            timestamp_span[s]+=(timestamp-last_time[s])&0xffffffff
                        else: first_time[s]=timestamp
                        previous[s]=sequence;last_time[s]=timestamp;counts[s]+=1
                        invalid[s]+=data[offset+(14 if s==0 else 10 if s==1 else 15)]==0
                        offset+=sizes[s]
    except Exception as exc:
        error=str(exc)
    elapsed=time.monotonic()-started
    try: after=status(base)
    except Exception as exc: after={'error':str(exc)}
    ordered=sorted(intervals)
    return dict(before=before,after=after,elapsedSeconds=elapsed,packets=packets,
                streamOrder=['ECG','MIC','IMU'],reportedRates=rates,samples=counts,
                receivedPerWallSecond=[round(n/elapsed,3) for n in counts],
                sourceRates=[round((counts[s]+gaps[s]-1)*1e6/timestamp_span[s],3) if timestamp_span[s] else None for s in range(3)],
                gaps=gaps,duplicateOrReordered=duplicates,invalid=invalid,cursorGapPackets=cursor_gaps,
                packetMedianMs=statistics.median(intervals) if intervals else None,
                packetP95Ms=ordered[min(len(ordered)-1,int(len(ordered)*0.95))] if ordered else None,
                maximumStallMs=max(intervals) if intervals else None,error=error,
                continuityPassed=error is None and packets>0 and all(counts) and not any(gaps) and not any(duplicates))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url',required=True)
    parser.add_argument('--duration',type=float,default=30)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if not 1<=args.duration<=3600: parser.error('duration must be 1..3600 seconds')
    report=run(args.base_url.rstrip('/'),args.duration)
    rendered=json.dumps(report,indent=2)
    if args.output: args.output.write_text(rendered+'\n',encoding='utf-8')
    print(rendered)
    raise SystemExit(0 if report['continuityPassed'] else 1)
