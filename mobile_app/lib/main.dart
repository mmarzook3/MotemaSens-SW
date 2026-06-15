import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

import 'app_update_banner.dart';
import 'app_update_service.dart';

void main() {
  runApp(const MotemaSensApp());
}

class MotemaSensApp extends StatelessWidget {
  const MotemaSensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotemaSens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const ConnectionChooserScreen(),
    );
  }
}

enum ConnectionStateKind { offline, connecting, connected }

enum RecordingMode { idle, ecg, microphone, imu, all, mixed }

enum LoggingChannel { ecg, mic, imu }

enum OtaMethod { localWifi, remote, ble }

final Guid motemaBleServiceUuid = Guid('9f6d0001-6f2b-4e45-9f2f-6b4f4d53454e');
final Guid motemaBleStatusUuid = Guid('9f6d0002-6f2b-4e45-9f2f-6b4f4d53454e');
final Guid motemaBleCommandUuid = Guid('9f6d0003-6f2b-4e45-9f2f-6b4f4d53454e');
final Guid motemaBleWifiProvisionUuid =
    Guid('9f6d0004-6f2b-4e45-9f2f-6b4f4d53454e');

const String developerPassword = '1234';
const String defaultRemoteApiBase = 'https://ms.nwatt.uk';
const String defaultRemoteUsername = 'test';
const String defaultRemotePassword = 'motemasens';
const String publicSoftwareManifestUrl =
    'https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/manifest.json';
const MethodChannel downloadsChannel =
    MethodChannel('uk.nwatt.motemasens/downloads');

double _jsonDouble(
  Map<String, dynamic> json,
  List<String> keys, {
  double fallback = 0,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return fallback;
}

int? _jsonIntOrNull(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

bool _jsonBool(Map<String, dynamic> json, List<String> keys) {
  return _jsonBoolOrNull(json, keys) ?? false;
}

bool? _jsonBoolOrNull(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalised = value.trim().toLowerCase();
      if (normalised == 'true' || normalised == '1' || normalised == 'yes') {
        return true;
      }
      if (normalised == 'false' || normalised == '0' || normalised == 'no') {
        return false;
      }
    }
  }
  return null;
}

int _estimateBatterySocFromVoltage(double volts) {
  const curve = <(double, int)>[
    (4.20, 100),
    (4.10, 90),
    (4.00, 80),
    (3.92, 70),
    (3.85, 60),
    (3.79, 50),
    (3.75, 40),
    (3.70, 30),
    (3.64, 20),
    (3.55, 10),
    (3.40, 0),
  ];
  if (volts >= curve.first.$1) {
    return 100;
  }
  if (volts <= curve.last.$1) {
    return 0;
  }
  for (var i = 0; i < curve.length - 1; i++) {
    final high = curve[i];
    final low = curve[i + 1];
    if (volts <= high.$1 && volts >= low.$1) {
      final span = high.$1 - low.$1;
      final t = span <= 0 ? 0.0 : (volts - low.$1) / span;
      return (low.$2 + (t * (high.$2 - low.$2))).round().clamp(0, 100);
    }
  }
  return 0;
}

class FirmwareFile {
  const FirmwareFile({
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory FirmwareFile.fromJson(Map<String, dynamic> json) {
    return FirmwareFile(
      url: (json['url'] as String?) ?? '',
      sha256: (json['sha256'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  final String url;
  final String sha256;
  final int size;
}

class SoftwareRelease {
  const SoftwareRelease({
    required this.publicVersion,
    required this.firmwareVersion,
    required this.releaseDate,
    required this.notes,
    required this.firmware,
    required this.minimumBatterySoc,
    required this.requiresPartitionScheme,
    required this.rollbackSupported,
  });

  factory SoftwareRelease.fromJson(Map<String, dynamic> json) {
    final files = json['files'];
    final firmwareJson = files is Map<String, dynamic>
        ? (files['firmware'] as Map<String, dynamic>? ?? const {})
        : (json['firmware'] as Map<String, dynamic>? ?? const {});
    return SoftwareRelease(
      publicVersion: (json['publicVersion'] as String?) ??
          (json['version'] as String?) ??
          '',
      firmwareVersion: (json['firmwareVersion'] as String?) ??
          (json['firmware_version'] as String?) ??
          (json['version'] as String?) ??
          '',
      releaseDate: (json['releaseDate'] as String?) ??
          (json['release_date'] as String?) ??
          '',
      notes: (json['notes'] as String?) ?? '',
      firmware: FirmwareFile.fromJson(firmwareJson),
      minimumBatterySoc: (json['minimumBatterySoc'] as num?)?.toInt() ??
          (json['minimum_battery_soc'] as num?)?.toInt() ??
          30,
      requiresPartitionScheme: (json['requiresPartitionScheme'] as String?) ??
          (json['requires_partition_scheme'] as String?) ??
          'ota_16mb_v1',
      rollbackSupported: json['rollbackSupported'] != false,
    );
  }

  final String publicVersion;
  final String firmwareVersion;
  final String releaseDate;
  final String notes;
  final FirmwareFile firmware;
  final int minimumBatterySoc;
  final String requiresPartitionScheme;
  final bool rollbackSupported;
}

class SoftwareManifest {
  const SoftwareManifest({required this.latest, required this.releases});

  factory SoftwareManifest.fromJson(Map<String, dynamic> json) {
    final raw =
        (json['releases'] as List?) ?? (json['versions'] as List?) ?? [];
    final releases = raw
        .whereType<Map<String, dynamic>>()
        .map(SoftwareRelease.fromJson)
        .where((release) =>
            release.publicVersion.isNotEmpty &&
            release.firmware.url.isNotEmpty &&
            release.firmware.sha256.length == 64 &&
            release.firmware.size > 0)
        .toList();
    return SoftwareManifest(
      latest: (json['latest'] as String?) ??
          (releases.isNotEmpty ? releases.first.publicVersion : ''),
      releases: releases,
    );
  }

  final String latest;
  final List<SoftwareRelease> releases;
}

class OtaProgress {
  const OtaProgress({
    required this.updateId,
    required this.method,
    required this.phase,
    required this.bytesDone,
    required this.bytesTotal,
    required this.percent,
    required this.message,
    required this.error,
  });

  factory OtaProgress.idle() => const OtaProgress(
        updateId: '',
        method: 'none',
        phase: 'idle',
        bytesDone: 0,
        bytesTotal: 0,
        percent: 0,
        message: 'idle',
        error: '',
      );

  factory OtaProgress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return OtaProgress.idle();
    return OtaProgress(
      updateId: (json['updateId'] as String?) ?? (json['u'] as String?) ?? '',
      method: (json['method'] as String?) ?? (json['m'] as String?) ?? 'none',
      phase: (json['phase'] as String?) ??
          (json['lastUpdateStatus'] as String?) ??
          (json['p'] as String?) ??
          'idle',
      bytesDone: (json['bytesDone'] as num?)?.toInt() ??
          (json['d'] as num?)?.toInt() ??
          0,
      bytesTotal: (json['bytesTotal'] as num?)?.toInt() ??
          (json['t'] as num?)?.toInt() ??
          0,
      percent: (json['percent'] as num?)?.toInt() ??
          (json['pc'] as num?)?.toInt() ??
          0,
      message: (json['message'] as String?) ?? '',
      error: (json['error'] as String?) ??
          (json['lastUpdateError'] as String?) ??
          (json['e'] as String?) ??
          '',
    );
  }

  final String updateId;
  final String method;
  final String phase;
  final int bytesDone;
  final int bytesTotal;
  final int percent;
  final String message;
  final String error;

  bool get isTerminal =>
      phase == 'success' ||
      phase == 'failed' ||
      phase == 'rolled_back' ||
      phase == 'cancelled';
}

int _batterySocFromJson(Map<String, dynamic> json, double volts) {
  final explicit = _jsonIntOrNull(json, const [
    'batterySoc',
    'battery_soc',
    'batteryPercent',
    'batteryPct',
    'battery_percent',
    'soc',
    'bs',
  ]);
  if (explicit != null) {
    return explicit.clamp(0, 100);
  }
  if (volts > 0) {
    return _estimateBatterySocFromVoltage(volts);
  }
  return 0;
}

bool _batteryPresentFromJson(Map<String, dynamic> json, double volts) {
  final status =
      (json['batteryStatus'] ?? json['battery_status'] ?? json['bst'])
          ?.toString()
          .trim()
          .toLowerCase();
  if (status == 'no_battery' || status == 'none' || status == 'missing') {
    return false;
  }
  if (status == 'ok' || status == 'charging') {
    return true;
  }
  final explicit = _jsonBoolOrNull(json, const [
    'batteryPresent',
    'battery_present',
    'hasBattery',
    'has_battery',
    'bp',
  ]);
  if (explicit != null) {
    return explicit;
  }
  if (volts > 0 && volts < 1.0) {
    return false;
  }
  return true;
}

String _batteryStatusText(
    double volts, int soc, bool charging, bool batteryPresent) {
  if (!batteryPresent) {
    return 'No Battery';
  }
  if (volts <= 0) {
    return 'No data';
  }
  return '${volts.toStringAsFixed(2)} V / $soc%${charging ? ' CHG' : ''}';
}

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.deviceSerial,
    required this.greenLed,
    required this.blueLed,
    required this.sw1Pressed,
    required this.sw2Pressed,
    required this.batteryVolts,
    required this.batterySoc,
    required this.batteryCharging,
    required this.batteryPresent,
    required this.signalQuality,
    required this.sampleRate,
    required this.sdReady,
    required this.sdLogging,
    required this.sdFreeGb,
    required this.sdSamples,
    required this.sdDropped,
    required this.sdPath,
    required this.recordingMode,
    required this.lastSeen,
    required this.version,
    required this.ip,
    required this.ledMode,
    required this.ledsOffOverride,
    required this.wifiLogging,
    required this.usbLogging,
    required this.logEcg,
    required this.logMic,
    required this.logImu,
    required this.selfTestActive,
    required this.micTrace,
    required this.ecgCh1,
    required this.ecgCh2,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.ota,
  });

  factory DeviceSnapshot.empty({
    bool greenLed = false,
    bool blueLed = false,
    RecordingMode recordingMode = RecordingMode.idle,
  }) {
    return DeviceSnapshot(
      deviceSerial: 0,
      greenLed: greenLed,
      blueLed: blueLed,
      sw1Pressed: false,
      sw2Pressed: true,
      batteryVolts: 4.08,
      batterySoc: 92,
      batteryCharging: false,
      batteryPresent: true,
      signalQuality: 92,
      sampleRate: 500,
      sdReady: false,
      sdLogging: false,
      sdFreeGb: 0,
      sdSamples: 0,
      sdDropped: 0,
      sdPath: '',
      recordingMode: recordingMode,
      lastSeen: DateTime.now(),
      version: 'not connected',
      ip: 'not connected',
      ledMode: 'heartbeat',
      ledsOffOverride: false,
      wifiLogging: false,
      usbLogging: false,
      logEcg: recordingMode == RecordingMode.ecg ||
          recordingMode == RecordingMode.all,
      logMic: recordingMode == RecordingMode.microphone ||
          recordingMode == RecordingMode.all,
      logImu: recordingMode == RecordingMode.imu ||
          recordingMode == RecordingMode.all,
      selfTestActive: false,
      micTrace: 0,
      ecgCh1: 0,
      ecgCh2: 0,
      accX: 0,
      accY: 0,
      accZ: 0,
      ota: OtaProgress.idle(),
    );
  }

  factory DeviceSnapshot.fromJson(Map<String, dynamic> json) {
    RecordingMode mode;
    final recordingMode = json['recordingMode'] ??
        json['rm'] ??
        ((json['wifi_logging'] == true) ? 'ecg' : 'idle');
    switch (recordingMode) {
      case 'ecg':
        mode = RecordingMode.ecg;
      case 'microphone':
        mode = RecordingMode.microphone;
      case 'imu':
        mode = RecordingMode.imu;
      case 'all':
        mode = RecordingMode.all;
      case 'mixed':
        mode = RecordingMode.mixed;
      default:
        mode = RecordingMode.idle;
    }
    final channels = json['logging_channels'];
    final logEcg = channels is Map
        ? channels['ecg'] == true
        : mode == RecordingMode.ecg || mode == RecordingMode.all;
    final logMic = channels is Map
        ? channels['mic'] == true
        : mode == RecordingMode.microphone || mode == RecordingMode.all;
    final logImu = channels is Map
        ? channels['imu'] == true
        : mode == RecordingMode.imu || mode == RecordingMode.all;

    final signalQuality = (json['signalQuality'] as num?)?.toInt() ??
        ((json['ecg_ready'] == true) ? 100 : 35);
    final wifiRate = (json['wifi_rate_hz'] as num?)?.round() ?? 0;

    final batteryVolts = _jsonDouble(json, const [
      'batteryVolts',
      'battery_volts',
      'batteryVoltage',
      'battery_voltage',
      'bv',
    ]);
    final batteryPresent = _batteryPresentFromJson(json, batteryVolts);
    return DeviceSnapshot(
      deviceSerial: _jsonIntOrNull(json, const [
            'deviceSerial',
            'sn',
          ]) ??
          0,
      greenLed: json['greenLed'] == true,
      blueLed: json['blueLed'] == true,
      sw1Pressed: json['sw1Pressed'] == true,
      sw2Pressed: json['sw2Pressed'] == true,
      batteryVolts: batteryVolts,
      batterySoc: _batterySocFromJson(json, batteryVolts),
      batteryCharging: _jsonBool(json, const [
            'batteryCharging',
            'battery_charging',
            'charging',
            'isCharging',
            'bc',
          ]) &&
          batteryPresent,
      batteryPresent: batteryPresent,
      signalQuality: signalQuality.clamp(0, 100),
      sampleRate: _jsonIntOrNull(json, const [
            'sampleRate',
            'fs',
          ]) ??
          (wifiRate > 0 ? wifiRate : 100),
      sdReady: _jsonBool(json, const [
        'sdReady',
        'sr',
      ]),
      sdLogging: _jsonBool(json, const [
        'sdLogging',
        'sd_logging',
        'sl',
      ]),
      sdFreeGb: (json['sdFreeGb'] as num?)?.toDouble() ?? 0,
      sdSamples: (json['sdSamples'] as num?)?.toInt() ?? 0,
      sdDropped: (json['sdDropped'] as num?)?.toInt() ?? 0,
      sdPath: (json['sdPath'] as String?) ?? '',
      recordingMode: mode,
      lastSeen: DateTime.now(),
      version:
          (json['version'] as String?) ?? (json['v'] as String?) ?? 'unknown',
      ip: (json['ip'] as String?) ?? '',
      ledMode: (json['ledMode'] as String?) ??
          (json['lm'] as String?) ??
          'heartbeat',
      ledsOffOverride: _jsonBool(json, const [
        'ledsOffOverride',
        'lo',
      ]),
      wifiLogging: json['wifi_logging'] == true,
      usbLogging: json['usb_logging'] == true,
      logEcg: logEcg,
      logMic: logMic,
      logImu: logImu,
      selfTestActive: json['selfTestActive'] == true,
      micTrace: (json['mic_trace'] as num?)?.toDouble() ?? 0,
      ecgCh1: (json['ecg_ch1'] as num?)?.toDouble() ?? 0,
      ecgCh2: (json['ecg_ch2'] as num?)?.toDouble() ?? 0,
      accX: (json['acc_x'] as num?)?.toDouble() ?? 0,
      accY: (json['acc_y'] as num?)?.toDouble() ?? 0,
      accZ: (json['acc_z'] as num?)?.toDouble() ?? 0,
      ota: OtaProgress.fromJson(json['ota'] is Map<String, dynamic>
          ? json['ota'] as Map<String, dynamic>
          : null),
    );
  }

  final int deviceSerial;
  final bool greenLed;
  final bool blueLed;
  final bool sw1Pressed;
  final bool sw2Pressed;
  final double batteryVolts;
  final int batterySoc;
  final bool batteryCharging;
  final bool batteryPresent;
  final int signalQuality;
  final int sampleRate;
  final bool sdReady;
  final bool sdLogging;
  final double sdFreeGb;
  final int sdSamples;
  final int sdDropped;
  final String sdPath;
  final RecordingMode recordingMode;
  final DateTime lastSeen;
  final String version;
  final String ip;
  final String ledMode;
  final bool ledsOffOverride;
  final bool wifiLogging;
  final bool usbLogging;
  final bool logEcg;
  final bool logMic;
  final bool logImu;
  final bool selfTestActive;
  final double micTrace;
  final double ecgCh1;
  final double ecgCh2;
  final double accX;
  final double accY;
  final double accZ;
  final OtaProgress ota;

  DeviceSnapshot copyWith({
    int? deviceSerial,
    bool? greenLed,
    bool? blueLed,
    bool? sw1Pressed,
    bool? sw2Pressed,
    double? batteryVolts,
    int? batterySoc,
    bool? batteryCharging,
    bool? batteryPresent,
    int? signalQuality,
    int? sampleRate,
    bool? sdReady,
    bool? sdLogging,
    double? sdFreeGb,
    int? sdSamples,
    int? sdDropped,
    String? sdPath,
    RecordingMode? recordingMode,
    DateTime? lastSeen,
    String? version,
    String? ip,
    String? ledMode,
    bool? ledsOffOverride,
    bool? wifiLogging,
    bool? usbLogging,
    bool? logEcg,
    bool? logMic,
    bool? logImu,
    bool? selfTestActive,
    double? micTrace,
    double? ecgCh1,
    double? ecgCh2,
    double? accX,
    double? accY,
    double? accZ,
    OtaProgress? ota,
  }) {
    return DeviceSnapshot(
      deviceSerial: deviceSerial ?? this.deviceSerial,
      greenLed: greenLed ?? this.greenLed,
      blueLed: blueLed ?? this.blueLed,
      sw1Pressed: sw1Pressed ?? this.sw1Pressed,
      sw2Pressed: sw2Pressed ?? this.sw2Pressed,
      batteryVolts: batteryVolts ?? this.batteryVolts,
      batterySoc: batterySoc ?? this.batterySoc,
      batteryCharging: batteryCharging ?? this.batteryCharging,
      batteryPresent: batteryPresent ?? this.batteryPresent,
      signalQuality: signalQuality ?? this.signalQuality,
      sampleRate: sampleRate ?? this.sampleRate,
      sdReady: sdReady ?? this.sdReady,
      sdLogging: sdLogging ?? this.sdLogging,
      sdFreeGb: sdFreeGb ?? this.sdFreeGb,
      sdSamples: sdSamples ?? this.sdSamples,
      sdDropped: sdDropped ?? this.sdDropped,
      sdPath: sdPath ?? this.sdPath,
      recordingMode: recordingMode ?? this.recordingMode,
      lastSeen: lastSeen ?? this.lastSeen,
      version: version ?? this.version,
      ip: ip ?? this.ip,
      ledMode: ledMode ?? this.ledMode,
      ledsOffOverride: ledsOffOverride ?? this.ledsOffOverride,
      wifiLogging: wifiLogging ?? this.wifiLogging,
      usbLogging: usbLogging ?? this.usbLogging,
      logEcg: logEcg ?? this.logEcg,
      logMic: logMic ?? this.logMic,
      logImu: logImu ?? this.logImu,
      selfTestActive: selfTestActive ?? this.selfTestActive,
      micTrace: micTrace ?? this.micTrace,
      ecgCh1: ecgCh1 ?? this.ecgCh1,
      ecgCh2: ecgCh2 ?? this.ecgCh2,
      accX: accX ?? this.accX,
      accY: accY ?? this.accY,
      accZ: accZ ?? this.accZ,
      ota: ota ?? this.ota,
    );
  }

  Set<LoggingChannel> get loggingChannels => {
        if (logEcg) LoggingChannel.ecg,
        if (logMic) LoggingChannel.mic,
        if (logImu) LoggingChannel.imu,
      };
}

class SdLogFile {
  const SdLogFile({required this.name, required this.sizeBytes});

  factory SdLogFile.fromJson(Map<String, dynamic> json) {
    return SdLogFile(
      name: (json['name'] as String?) ?? '',
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final int sizeBytes;

  String get displaySize {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes B';
  }
}

class MotemaSensBinaryLogConverter {
  static const csvHeader =
      'LOG_HEADER,ms,ecg_us,ecg_seq8,ecg_seq,ecg_status,lead_i_raw,lead_ii_raw,lead_iii_raw,lead_off_p,lead_off_n,sat_mask,diag_flags,mic_ms,mic_seq8,mic_trace,mic_level,acc_ms,acc_seq8,acc_x_g,acc_y_g,acc_z_g,raw_x,raw_y,raw_z,acc_diag_flags';

  static bool looksLikeBinaryLog(Uint8List bytes) {
    if (bytes.length < 64) return false;
    return ascii.decode(bytes.sublist(0, 7), allowInvalid: true) == 'MSLOGB1';
  }

  static String convert(Uint8List bytes, {int? maxRows}) {
    if (!looksLikeBinaryLog(bytes)) {
      return utf8.decode(bytes, allowMalformed: true);
    }

    final data = ByteData.sublistView(bytes);
    final headerSize = data.getUint16(8, Endian.little);
    final recordSize = data.getUint16(10, Endian.little);
    if (headerSize < 64 || recordSize != 64 || bytes.length < headerSize) {
      throw const FormatException('Bad MotemaSens binary log');
    }

    final out = StringBuffer(csvHeader)..writeln();
    var offset = headerSize;
    var rows = 0;
    while (offset + recordSize <= bytes.length) {
      if (maxRows != null && rows >= maxRows) {
        break;
      }
      final elapsedMs = data.getUint32(offset + 0, Endian.little);
      final ecgUs = data.getUint32(offset + 4, Endian.little);
      final ecgSeq = data.getUint32(offset + 8, Endian.little);
      final ecgStatus = data.getUint32(offset + 12, Endian.little);
      final leadI = data.getInt32(offset + 16, Endian.little);
      final leadII = data.getInt32(offset + 20, Endian.little);
      final leadIII = data.getInt32(offset + 24, Endian.little);
      final micMs = data.getUint32(offset + 28, Endian.little);
      final accMs = data.getUint32(offset + 32, Endian.little);
      final micTrace = data.getInt16(offset + 36, Endian.little) / 32767.0;
      final micLevel = data.getInt16(offset + 38, Endian.little) / 32767.0;
      final accX = data.getInt16(offset + 40, Endian.little) / 1000.0;
      final accY = data.getInt16(offset + 42, Endian.little) / 1000.0;
      final accZ = data.getInt16(offset + 44, Endian.little) / 1000.0;
      final rawX = data.getInt16(offset + 46, Endian.little);
      final rawY = data.getInt16(offset + 48, Endian.little);
      final rawZ = data.getInt16(offset + 50, Endian.little);
      final diagFlags = data.getUint16(offset + 52, Endian.little);
      final ecgSeq8 = data.getUint8(offset + 54);
      final leadOffP = data.getUint8(offset + 55);
      final leadOffN = data.getUint8(offset + 56);
      final satMask = data.getUint8(offset + 57);
      final micSeq8 = data.getUint8(offset + 58);
      final accSeq8 = data.getUint8(offset + 59);
      final accDiagFlags = data.getUint8(offset + 60);

      out
        ..write('LOG,')
        ..write(elapsedMs)
        ..write(',')
        ..write(ecgUs)
        ..write(',')
        ..write(ecgSeq8)
        ..write(',')
        ..write(ecgSeq)
        ..write(',')
        ..write(ecgStatus.toRadixString(16).toUpperCase().padLeft(6, '0'))
        ..write(',')
        ..write(leadI)
        ..write(',')
        ..write(leadII)
        ..write(',')
        ..write(leadIII)
        ..write(',')
        ..write(leadOffP.toRadixString(16).toUpperCase().padLeft(2, '0'))
        ..write(',')
        ..write(leadOffN.toRadixString(16).toUpperCase().padLeft(2, '0'))
        ..write(',')
        ..write(satMask.toRadixString(16).toUpperCase().padLeft(2, '0'))
        ..write(',')
        ..write(diagFlags.toRadixString(16).toUpperCase().padLeft(4, '0'))
        ..write(',')
        ..write(micMs)
        ..write(',')
        ..write(micSeq8)
        ..write(',')
        ..write(micTrace.toStringAsFixed(4))
        ..write(',')
        ..write(micLevel.toStringAsFixed(4))
        ..write(',')
        ..write(accMs)
        ..write(',')
        ..write(accSeq8)
        ..write(',')
        ..write(accX.toStringAsFixed(4))
        ..write(',')
        ..write(accY.toStringAsFixed(4))
        ..write(',')
        ..write(accZ.toStringAsFixed(4))
        ..write(',')
        ..write(rawX)
        ..write(',')
        ..write(rawY)
        ..write(',')
        ..write(rawZ)
        ..write(',')
        ..write(accDiagFlags.toRadixString(16).toUpperCase().padLeft(2, '0'))
        ..writeln();

      offset += recordSize;
      rows++;
    }
    return out.toString();
  }
}

class DeviceApi {
  DeviceApi({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<DeviceSnapshot> fetchStatus() async {
    final response = await _client
        .get(_uri('/api/status'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw Exception('Status failed: HTTP ${response.statusCode}');
    }
    return DeviceSnapshot.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> setLed({required String led, required bool enabled}) async {
    await _post('/api/led', {'led': led, 'enabled': enabled});
  }

  Future<void> setLedHeartbeat() async {
    await _post('/api/led-heartbeat', {});
  }

  Future<void> setLedOffOverride(bool enabled) async {
    await _post('/api/led-off-override', {'enabled': enabled});
  }

  Future<void> setRecording(RecordingMode mode) async {
    final value = switch (mode) {
      RecordingMode.ecg => 'ecg',
      RecordingMode.microphone => 'microphone',
      RecordingMode.imu => 'imu',
      RecordingMode.all => 'all',
      RecordingMode.mixed => 'all',
      RecordingMode.idle => 'idle',
    };
    await _post('/api/recording', {'mode': value});
  }

  Future<void> setRecordingChannels(Set<LoggingChannel> channels) async {
    if (channels.isEmpty) {
      await _post('/api/recording', {'mode': 'idle'});
      return;
    }
    await _post('/api/recording', {
      'ecg': channels.contains(LoggingChannel.ecg),
      'mic': channels.contains(LoggingChannel.mic),
      'imu': channels.contains(LoggingChannel.imu),
    });
  }

  Future<Map<String, dynamic>> fetchStreamStatus() async {
    final response = await _client
        .get(_uri('/api/stream/status'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Stream status failed: HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchFiles() async {
    final response = await _client
        .get(_uri('/api/files'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Files failed: HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<SdLogFile>> fetchSdFiles() async {
    final response = await _client
        .get(_uri('/api/files'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Files failed: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawFiles = (body['files'] as List<dynamic>?) ??
        (body['items'] as List<dynamic>?) ??
        const <dynamic>[];
    final files = rawFiles
        .whereType<Map<String, dynamic>>()
        .map(SdLogFile.fromJson)
        .where((file) => file.name.isNotEmpty)
        .toList();
    files.sort((a, b) => b.name.compareTo(a.name));
    return files;
  }

  Uri sdFileUri(String fileName) {
    return _uri('/api/sd/file?name=${Uri.encodeComponent(fileName)}');
  }

  Future<String> fetchSdFileCsvPreview(String fileName) async {
    final response = await _client
        .get(sdFileUri(fileName))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('SD file failed: HTTP ${response.statusCode}');
    }
    final csv = MotemaSensBinaryLogConverter.convert(
      response.bodyBytes,
      maxRows: fileName.toLowerCase().endsWith('.bin') ? 180 : null,
    );
    return csv.length > 16000 ? csv.substring(0, 16000) : csv;
  }

  Future<Uint8List> fetchSdFileBytes(String fileName) async {
    final response = await _client
        .get(sdFileUri(fileName))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('SD file failed: HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<void> runSelfTest() async {
    await _post('/api/self-test', {});
  }

  Future<void> reconnectWifi() async {
    await _post('/api/reconnect-wifi', {});
  }

  Future<void> restartDevice() async {
    await _post('/api/restart', {});
  }

  Future<OtaProgress> fetchOtaStatus() async {
    final response = await _client
        .get(_uri('/api/ota/status'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('OTA status failed: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OtaProgress.fromJson(body['ota'] as Map<String, dynamic>?);
  }

  Future<OtaProgress> beginOta({
    required String updateId,
    required SoftwareRelease release,
  }) async {
    final response = await _client
        .post(
          _uri('/api/ota/begin'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'updateId': updateId,
            'publicVersion': release.publicVersion,
            'firmwareVersion': release.firmwareVersion,
            'sha256': release.firmware.sha256,
            'size': release.firmware.size,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OTA begin failed: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OtaProgress.fromJson(body['ota'] as Map<String, dynamic>?);
  }

  Future<OtaProgress> uploadOtaChunk({
    required String updateId,
    required int offset,
    required Uint8List bytes,
  }) async {
    final response = await _client
        .post(
          _uri(
              '/api/ota/chunk?updateId=${Uri.encodeComponent(updateId)}&offset=$offset'),
          headers: const {'content-type': 'application/octet-stream'},
          body: bytes,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OTA chunk failed: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OtaProgress.fromJson(body['ota'] as Map<String, dynamic>?);
  }

  Future<OtaProgress> finishOta(String updateId) async {
    final response = await _client
        .post(
          _uri('/api/ota/finish'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'updateId': updateId}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OTA finish failed: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OtaProgress.fromJson(body['ota'] as Map<String, dynamic>?);
  }

  Future<void> cancelOta() async {
    await _post('/api/ota/cancel', {});
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    final response = await _client
        .post(
          _uri(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$path failed: HTTP ${response.statusCode}');
    }
  }
}

class RemoteDeviceSummary {
  const RemoteDeviceSummary({
    required this.deviceId,
    required this.deviceSerial,
    required this.name,
    required this.online,
    required this.lastSeen,
    required this.batteryVolts,
    required this.batterySoc,
    required this.batteryCharging,
    required this.batteryPresent,
    required this.signalQuality,
    required this.sampleRate,
    required this.recordingMode,
    required this.sdReady,
    required this.unsyncedChunks,
    required this.version,
  });

  factory RemoteDeviceSummary.fromJson(Map<String, dynamic> json) {
    final batteryVolts = _jsonDouble(json, const [
      'batteryVolts',
      'battery_volts',
      'batteryVoltage',
      'battery_voltage',
      'bv',
    ]);
    final batteryPresent = _batteryPresentFromJson(json, batteryVolts);
    return RemoteDeviceSummary(
      deviceId: (json['deviceId'] as String?) ?? '',
      deviceSerial: (json['deviceSerial'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? 'MotemaSens',
      online: json['online'] == true,
      lastSeen: (json['lastSeen'] as String?) ?? '',
      batteryVolts: batteryVolts,
      batterySoc: _batterySocFromJson(json, batteryVolts),
      batteryCharging: _jsonBool(json, const [
            'batteryCharging',
            'battery_charging',
            'charging',
            'isCharging',
            'bc',
          ]) &&
          batteryPresent,
      batteryPresent: batteryPresent,
      signalQuality: (json['signalQuality'] as num?)?.toInt() ?? 0,
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 0,
      recordingMode: (json['recordingMode'] as String?) ?? 'idle',
      sdReady: json['sdReady'] == true,
      unsyncedChunks: (json['unsyncedChunks'] as num?)?.toInt() ?? 0,
      version: (json['version'] as String?) ?? '',
    );
  }

  final String deviceId;
  final int deviceSerial;
  final String name;
  final bool online;
  final String lastSeen;
  final double batteryVolts;
  final int batterySoc;
  final bool batteryCharging;
  final bool batteryPresent;
  final int signalQuality;
  final int sampleRate;
  final String recordingMode;
  final bool sdReady;
  final int unsyncedChunks;
  final String version;
}

class RemoteApi {
  RemoteApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? _token;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final response = await _client
        .post(
          _uri('/api/auth/login'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Login failed');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _token = json['token'] as String?;
    if (_token == null || _token!.isEmpty) {
      throw Exception('Login token missing');
    }
  }

  Future<List<RemoteDeviceSummary>> fetchDevices() async {
    final response = await _client
        .get(_uri('/api/devices'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Device list failed');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final devices = (json['devices'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteDeviceSummary.fromJson)
        .toList();
    return devices;
  }

  Future<(DeviceSnapshot?, bool)> fetchDeviceStatus(String deviceId) async {
    final response = await _client
        .get(_uri('/api/devices/$deviceId/status'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Remote status failed');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final status = json['status'];
    return (
      status is Map<String, dynamic> ? DeviceSnapshot.fromJson(status) : null,
      json['online'] == true,
    );
  }

  Future<void> sendCommand(
    String deviceId,
    Map<String, Object?> command,
  ) async {
    final response = await _client
        .post(
          _uri('/api/devices/$deviceId/commands'),
          headers: _headers,
          body: jsonEncode(command),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Remote command failed');
    }
  }

  Future<SoftwareManifest> fetchSoftwareReleases() async {
    final response = await _client
        .get(_uri('/api/software/releases'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Release list failed: HTTP ${response.statusCode}');
    }
    return SoftwareManifest.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<String> startRemoteOta(
      String deviceId, SoftwareRelease release) async {
    final response = await _client
        .post(
          _uri('/api/devices/$deviceId/ota'),
          headers: _headers,
          body: jsonEncode({'publicVersion': release.publicVersion}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Remote OTA failed: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['updateId'] as String;
  }

  Future<(OtaProgress, DeviceSnapshot?)> fetchRemoteOtaProgress(
    String deviceId,
    String updateId,
  ) async {
    final response = await _client
        .get(_uri('/api/devices/$deviceId/ota/$updateId'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Remote OTA progress failed');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final status = body['status'];
    final deviceStatus = body['deviceStatus'];
    return (
      OtaProgress.fromJson(status is Map<String, dynamic> ? status : null),
      deviceStatus is Map<String, dynamic>
          ? DeviceSnapshot.fromJson(deviceStatus)
          : null,
    );
  }

  Future<void> cancelRemoteOta(String deviceId, String updateId) async {
    final response = await _client
        .post(
          _uri('/api/devices/$deviceId/ota/$updateId/cancel'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Remote OTA cancel failed');
    }
  }

  Future<Map<String, dynamic>> fetchSessions(String deviceId) async {
    final response = await _client
        .get(_uri('/api/devices/$deviceId/sessions'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Remote sessions failed');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class BleDeviceClient {
  BleDeviceClient(this.device);

  final BluetoothDevice device;
  BluetoothCharacteristic? _statusCharacteristic;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _wifiProvisionCharacteristic;

  String get displayName {
    final name =
        device.advName.isNotEmpty ? device.advName : device.platformName;
    return name.isNotEmpty ? name : device.remoteId.str;
  }

  Future<void> connect() async {
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 12),
      mtu: 256,
    );
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid != motemaBleServiceUuid) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == motemaBleStatusUuid) {
          _statusCharacteristic = characteristic;
        } else if (characteristic.uuid == motemaBleCommandUuid) {
          _commandCharacteristic = characteristic;
        } else if (characteristic.uuid == motemaBleWifiProvisionUuid) {
          _wifiProvisionCharacteristic = characteristic;
        }
      }
    }
    if (_statusCharacteristic == null ||
        _commandCharacteristic == null ||
        _wifiProvisionCharacteristic == null) {
      throw Exception('MotemaSens BLE service incomplete');
    }
    await _statusCharacteristic!.setNotifyValue(true);
  }

  Future<void> disconnect() async {
    await device.disconnect();
  }

  Stream<BluetoothConnectionState> get connectionState =>
      device.connectionState;

  Future<bool> get isConnected async =>
      await device.connectionState.first == BluetoothConnectionState.connected;

  Future<DeviceSnapshot> readStatus() async {
    final json = await _readJsonCharacteristic(_statusCharacteristic!);
    return DeviceSnapshot.fromJson(json);
  }

  Future<Map<String, dynamic>> sendCommand(Map<String, Object?> command) async {
    await _commandCharacteristic!.write(
      utf8.encode(jsonEncode(command)),
      withoutResponse: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _readJsonCharacteristic(_commandCharacteristic!);
  }

  Future<Map<String, dynamic>> setLedOffOverride(bool enabled) {
    return sendCommand({
      'command': 'set_leds_off_override',
      'enabled': enabled,
    });
  }

  Future<Map<String, dynamic>> provisionWifi({
    required String ssid,
    required String password,
  }) async {
    await _wifiProvisionCharacteristic!.write(
      utf8.encode(jsonEncode({
        'command': 'configure_wifi',
        'ssid': ssid,
        'password': password,
      })),
      withoutResponse: false,
      allowLongWrite: true,
    );
    await Future<void>.delayed(const Duration(seconds: 4));
    return _readJsonCharacteristic(_wifiProvisionCharacteristic!);
  }

  Future<Map<String, dynamic>> _readJsonCharacteristic(
    BluetoothCharacteristic characteristic,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      final bytes = await characteristic.read();
      final payload = utf8.decode(bytes).trim();
      if (payload.isNotEmpty) {
        return jsonDecode(payload) as Map<String, dynamic>;
      }
      lastError = const FormatException('empty BLE response');
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    throw lastError ?? const FormatException('empty BLE response');
  }
}

class SoftwareUpdateScreen extends StatefulWidget {
  const SoftwareUpdateScreen({
    super.key,
    required this.method,
    required this.currentVersion,
    this.localApi,
    this.remoteApi,
    this.remoteDeviceId,
  });

  final OtaMethod method;
  final String currentVersion;
  final DeviceApi? localApi;
  final RemoteApi? remoteApi;
  final String? remoteDeviceId;

  @override
  State<SoftwareUpdateScreen> createState() => _SoftwareUpdateScreenState();
}

class _SoftwareUpdateScreenState extends State<SoftwareUpdateScreen> {
  List<SoftwareRelease> _releases = [];
  SoftwareRelease? _selected;
  OtaProgress _progress = OtaProgress.idle();
  String _message = 'Loading releases';
  bool _busy = false;
  bool _done = false;
  int _downloadPercent = 0;
  int _transferPercent = 0;
  int _flashPercent = 0;

  @override
  void initState() {
    super.initState();
    _loadReleases();
  }

  Future<void> _loadReleases() async {
    setState(() {
      _busy = true;
      _message = 'Loading releases';
    });
    try {
      final manifest =
          widget.method == OtaMethod.remote && widget.remoteApi != null
              ? await widget.remoteApi!.fetchSoftwareReleases()
              : await _fetchPublicManifest();
      setState(() {
        _releases = manifest.releases;
        _selected = manifest.releases.firstWhere(
          (item) => item.publicVersion == manifest.latest,
          orElse: () => manifest.releases.isNotEmpty
              ? manifest.releases.first
              : throw Exception('No releases found'),
        );
        _message = _releases.isEmpty ? 'No releases found' : 'Ready';
      });
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<SoftwareManifest> _fetchPublicManifest() async {
    final response = await http
        .get(Uri.parse(publicSoftwareManifestUrl))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Release manifest failed: HTTP ${response.statusCode}');
    }
    return SoftwareManifest.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Uint8List> _downloadFirmware(SoftwareRelease release) async {
    final request = http.Request('GET', Uri.parse(release.firmware.url));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw Exception('Firmware download failed: HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? release.firmware.size;
    final chunks = <int>[];
    var received = 0;
    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
      received += chunk.length;
      setState(() => _downloadPercent =
          total > 0 ? ((received * 100) / total).floor().clamp(0, 100) : 0);
    }
    final bytes = Uint8List.fromList(chunks);
    final digest = sha256.convert(bytes).toString();
    if (digest != release.firmware.sha256) {
      throw Exception('Firmware file checksum failed.');
    }
    return bytes;
  }

  Future<void> _startUpdate() async {
    final release = _selected;
    if (release == null || _busy) return;
    if (widget.method == OtaMethod.ble) {
      setState(() => _message =
          'BLE OTA is disabled for now. Use Local WiFi or Remote OTA.');
      return;
    }
    setState(() {
      _busy = true;
      _done = false;
      _downloadPercent = 0;
      _transferPercent = 0;
      _flashPercent = 0;
      _message = 'Starting update';
      _progress = OtaProgress.idle();
    });
    try {
      if (widget.method == OtaMethod.remote) {
        await _runRemoteUpdate(release);
      } else {
        await _runLocalUpdate(release);
      }
    } catch (error) {
      setState(() {
        _message = error.toString();
        _progress = OtaProgress(
          updateId: _progress.updateId,
          method: _progress.method,
          phase: 'failed',
          bytesDone: _progress.bytesDone,
          bytesTotal: _progress.bytesTotal,
          percent: _progress.percent,
          message: _progress.message,
          error: error.toString(),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runLocalUpdate(SoftwareRelease release) async {
    final api = widget.localApi;
    if (api == null) throw Exception('Local device API not connected');
    setState(() => _message = 'Downloading firmware');
    final firmware = await _downloadFirmware(release);
    final updateId = 'local-${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _message = 'Sending update begin');
    _progress = await api.beginOta(updateId: updateId, release: release);
    const chunkSize = 4096;
    for (var offset = 0; offset < firmware.length; offset += chunkSize) {
      final end = math.min(offset + chunkSize, firmware.length);
      final chunk = Uint8List.sublistView(firmware, offset, end);
      _progress = await api.uploadOtaChunk(
          updateId: updateId, offset: offset, bytes: chunk);
      setState(() {
        _transferPercent = ((end * 100) / firmware.length).floor();
        _flashPercent = _progress.percent;
        _message = 'Transferring firmware';
      });
    }
    _progress = await api.finishOta(updateId);
    setState(() {
      _flashPercent = 100;
      _message = 'Device rebooting';
    });
    await _waitForLocalVersion(api, release.firmwareVersion);
  }

  Future<void> _waitForLocalVersion(
      DeviceApi api, String expectedVersion) async {
    for (var attempt = 0; attempt < 45; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final status = await api.fetchStatus();
        if (status.version == expectedVersion) {
          setState(() {
            _done = true;
            _progress = status.ota.phase == 'idle'
                ? OtaProgress(
                    updateId: _progress.updateId,
                    method: 'local',
                    phase: 'success',
                    bytesDone: _progress.bytesTotal,
                    bytesTotal: _progress.bytesTotal,
                    percent: 100,
                    message: 'Firmware version confirmed',
                    error: '',
                  )
                : status.ota;
            _message = 'Update confirmed: $expectedVersion';
          });
          return;
        }
      } catch (_) {
        // Expected during reboot.
      }
      setState(() => _message = 'Waiting for device to report new version');
    }
    throw Exception('Device rebooted but did not report the expected version.');
  }

  Future<void> _runRemoteUpdate(SoftwareRelease release) async {
    final api = widget.remoteApi;
    final deviceId = widget.remoteDeviceId;
    if (api == null || deviceId == null) {
      throw Exception('Remote API not connected');
    }
    final updateId = await api.startRemoteOta(deviceId, release);
    setState(() => _message = 'Remote update sent to device');
    for (var attempt = 0; attempt < 180; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final (progress, snapshot) =
          await api.fetchRemoteOtaProgress(deviceId, updateId);
      setState(() {
        _progress = progress;
        _transferPercent = progress.percent;
        _flashPercent = progress.percent;
        _message =
            progress.message.isNotEmpty ? progress.message : progress.phase;
      });
      if (snapshot?.version == release.firmwareVersion) {
        setState(() {
          _done = true;
          _message = 'Update confirmed: ${release.firmwareVersion}';
        });
        return;
      }
      if (progress.phase == 'failed' || progress.phase == 'rolled_back') {
        throw Exception(
            progress.error.isNotEmpty ? progress.error : progress.phase);
      }
    }
    throw Exception('Device did not confirm the expected firmware version.');
  }

  Future<void> _cancel() async {
    try {
      if (widget.method == OtaMethod.localWifi) {
        await widget.localApi?.cancelOta();
      } else if (widget.method == OtaMethod.remote &&
          widget.remoteApi != null &&
          widget.remoteDeviceId != null &&
          _progress.updateId.isNotEmpty) {
        await widget.remoteApi!
            .cancelRemoteOta(widget.remoteDeviceId!, _progress.updateId);
      }
      setState(() => _message = 'Cancel requested');
    } catch (error) {
      setState(() => _message = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final methodLabel = switch (widget.method) {
      OtaMethod.localWifi => 'Local WiFi',
      OtaMethod.remote => 'Remote VPS',
      OtaMethod.ble => 'BLE fallback',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Software Update')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.system_update_alt,
                  title: methodLabel,
                  trailing: _StatusPill(
                    label: _done ? 'Done' : (_busy ? 'Running' : 'Ready'),
                    tone:
                        _done ? _Tone.good : (_busy ? _Tone.warn : _Tone.good),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Current firmware: ${widget.currentVersion}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<SoftwareRelease>(
                  initialValue: _selected,
                  items: _releases
                      .map((release) => DropdownMenuItem(
                            value: release,
                            child: Text(
                                '${release.publicVersion}  ${release.firmwareVersion}'),
                          ))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _selected = value),
                  decoration: const InputDecoration(
                    labelText: 'Released firmware',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 8),
                  Text(_selected!.notes,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                if (widget.method == OtaMethod.ble) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'BLE OTA is disabled until Local WiFi and Remote OTA are fully stable.',
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy || widget.method == OtaMethod.ble
                            ? null
                            : _startUpdate,
                        icon: const Icon(Icons.system_update),
                        label: const Text('Start Update'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? _cancel : null,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_message),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                    icon: Icons.timeline_outlined, title: 'Progress'),
                const SizedBox(height: 12),
                _OtaProgressRow(
                    label: 'Downloading firmware', percent: _downloadPercent),
                _OtaProgressRow(
                    label: 'Transferring to device', percent: _transferPercent),
                _OtaProgressRow(label: 'Flashing', percent: _flashPercent),
                _OtaProgressRow(
                    label: 'Verifying',
                    percent: _progress.phase == 'verifying'
                        ? null
                        : (_done ? 100 : 0)),
                _OtaProgressRow(
                    label: 'Rebooting',
                    percent: _progress.phase == 'rebooting'
                        ? null
                        : (_done ? 100 : 0)),
                _OtaProgressRow(
                    label: 'Confirming version', percent: _done ? 100 : 0),
                if (_progress.error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_progress.error,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtaProgressRow extends StatelessWidget {
  const _OtaProgressRow({required this.label, required this.percent});

  final String label;
  final int? percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(percent == null ? 'running' : '$percent%'),
            ],
          ),
          const SizedBox(height: 4),
          percent == null
              ? const LinearProgressIndicator()
              : LinearProgressIndicator(value: percent!.clamp(0, 100) / 100),
        ],
      ),
    );
  }
}

class ConnectionChooserScreen extends StatefulWidget {
  const ConnectionChooserScreen({super.key});

  @override
  State<ConnectionChooserScreen> createState() =>
      _ConnectionChooserScreenState();
}

class _ConnectionChooserScreenState extends State<ConnectionChooserScreen> {
  final AppUpdateService _appUpdateService = AppUpdateService();
  AppUpdateState _appUpdateState = AppUpdateState.checking();

  @override
  void initState() {
    super.initState();
    _checkAppUpdate();
  }

  Future<void> _checkAppUpdate({bool force = false}) async {
    setState(() {
      _appUpdateState = AppUpdateState.checking(
        installedVersion: _appUpdateState.installedVersion,
      );
    });
    final state = await _appUpdateService.checkForUpdate(force: force);
    if (!mounted) return;
    setState(() => _appUpdateState = state);
  }

  Future<void> _startAppUpdate() async {
    final release = _appUpdateState.release;
    if (release == null) return;
    try {
      await _appUpdateService.startUpdate(release);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('App update failed: $error')),
      );
    }
  }

  Future<void> _remindLater() async {
    final state = await _appUpdateService.remindLater(_appUpdateState);
    if (!mounted) return;
    setState(() => _appUpdateState = state);
  }

  Future<void> _ignoreVersion() async {
    final state = await _appUpdateService.ignoreVersion(_appUpdateState);
    if (!mounted) return;
    setState(() => _appUpdateState = state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect To MotemaSens')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ConnectionChoiceCard(
            title: 'Local',
            subtitle: 'Connect by ESP32 IP address on the same WiFi.',
            icon: Icons.wifi_tethering,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LocalConnectScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _ConnectionChoiceCard(
            title: 'Remote',
            subtitle: 'Use the MotemaSens VPS dashboard from anywhere.',
            icon: Icons.cloud_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RemoteLoginScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _ConnectionChoiceCard(
            title: 'BLE',
            subtitle: 'Nearby fallback control without WiFi.',
            icon: Icons.bluetooth,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BleScanScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _ConnectionChoiceCard(
            title: 'Debug',
            subtitle: 'Locked support tools for WiFi setup and LED override.',
            icon: Icons.admin_panel_settings_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const DeveloperPasswordScreen()),
            ),
          ),
          const SizedBox(height: 12),
          AppUpdateBanner(
            state: _appUpdateState,
            onRetry: () => _checkAppUpdate(force: true),
            onUpdate: _startAppUpdate,
            onLater: _remindLater,
            onIgnore: _ignoreVersion,
          ),
        ],
      ),
    );
  }
}

class RemoteLoginScreen extends StatefulWidget {
  const RemoteLoginScreen({super.key});

  @override
  State<RemoteLoginScreen> createState() => _RemoteLoginScreenState();
}

class _RemoteLoginScreenState extends State<RemoteLoginScreen> {
  final _apiBaseController = TextEditingController(text: defaultRemoteApiBase);
  final _usernameController =
      TextEditingController(text: defaultRemoteUsername);
  final _passwordController =
      TextEditingController(text: defaultRemotePassword);
  bool _busy = false;
  bool _showPassword = false;
  String _message = 'Login to the MotemaSens cloud.';

  @override
  void dispose() {
    _apiBaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _message = 'Connecting...';
    });
    final api = RemoteApi(baseUrl: _apiBaseController.text.trim());
    try {
      await api.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RemoteDeviceListScreen(api: api)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Login')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                    icon: Icons.cloud_outlined, title: 'MotemaSens VPS'),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiBaseController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip:
                          _showPassword ? 'Hide password' : 'Show password',
                      icon: Icon(_showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () {
                        setState(() => _showPassword = !_showPassword);
                      },
                    ),
                  ),
                  obscureText: !_showPassword,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Login'),
                ),
                const SizedBox(height: 8),
                Text(_message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RemoteDeviceListScreen extends StatefulWidget {
  const RemoteDeviceListScreen({super.key, required this.api});

  final RemoteApi api;

  @override
  State<RemoteDeviceListScreen> createState() => _RemoteDeviceListScreenState();
}

class _RemoteDeviceListScreenState extends State<RemoteDeviceListScreen> {
  List<RemoteDeviceSummary> _devices = [];
  bool _busy = true;
  String _message = 'Loading devices...';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _message = 'Loading devices...';
    });
    try {
      final devices = await widget.api.fetchDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _message = devices.isEmpty ? 'No devices assigned.' : 'Ready';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Devices'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(_message),
          const SizedBox(height: 12),
          for (final device in _devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    device.online ? Icons.cloud_done : Icons.cloud_off,
                    color: device.online
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFB45309),
                  ),
                  title: Text(device.name),
                  subtitle: Text(
                    '${device.deviceSerial > 0 ? 'Serial #${device.deviceSerial.toString().padLeft(3, '0')}' : device.deviceId}  ${device.recordingMode}  ${device.signalQuality}%\n'
                    'Battery ${_batteryStatusText(device.batteryVolts, device.batterySoc, device.batteryCharging, device.batteryPresent)}\n'
                    'Last seen: ${device.lastSeen.isEmpty ? 'never' : device.lastSeen}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RemoteDeviceDashboardScreen(
                        api: widget.api,
                        device: device,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RemoteDeviceDashboardScreen extends StatefulWidget {
  const RemoteDeviceDashboardScreen({
    super.key,
    required this.api,
    required this.device,
  });

  final RemoteApi api;
  final RemoteDeviceSummary device;

  @override
  State<RemoteDeviceDashboardScreen> createState() =>
      _RemoteDeviceDashboardScreenState();
}

class _RemoteDeviceDashboardScreenState
    extends State<RemoteDeviceDashboardScreen> {
  Timer? _timer;
  DeviceSnapshot? _snapshot;
  bool _online = false;
  bool _busy = true;
  String _message = 'Loading remote status...';
  String _sdMessage = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final (snapshot, online) =
          await widget.api.fetchDeviceStatus(widget.device.deviceId);
      final sessions = await widget.api.fetchSessions(widget.device.deviceId);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _online = online;
        _message =
            snapshot == null ? 'Waiting for first device heartbeat.' : 'Ready';
        _sdMessage = (sessions['message'] as String?) ?? '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _command(Map<String, Object?> command) async {
    setState(() => _message = 'Sending command...');
    try {
      await widget.api.sendCommand(widget.device.deviceId, command);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _refresh();
      if (!mounted) return;
      setState(() => _message = 'Command sent');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    }
  }

  Future<void> _setChannels(Set<LoggingChannel> channels) {
    if (channels.isEmpty) {
      return _command({'command': 'stop_recording'});
    }
    return _command({
      'command': 'set_recording_channels',
      'ecg': channels.contains(LoggingChannel.ecg),
      'mic': channels.contains(LoggingChannel.mic),
      'imu': channels.contains(LoggingChannel.imu),
    });
  }

  Future<void> _reconnectWifi() {
    return _command({'command': 'reconnect_wifi'});
  }

  Future<void> _restartDevice() {
    setState(() => _message = 'Sending restart command...');
    return widget.api.sendCommand(
        widget.device.deviceId, {'command': 'restart_device'}).then((_) {
      if (!mounted) return;
      setState(() {
        _online = false;
        _message = 'Restart command sent. Wait for the device to boot.';
      });
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    });
  }

  void _openSoftwareUpdate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftwareUpdateScreen(
          method: OtaMethod.remote,
          currentVersion: (_snapshot ?? DeviceSnapshot.empty()).version,
          remoteApi: widget.api,
          remoteDeviceId: widget.device.deviceId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot ?? DeviceSnapshot.empty();
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(
                    icon: Icons.cloud_outlined,
                    title: widget.device.deviceId,
                    trailing: _StatusPill(
                      label: _online ? 'Online' : 'Offline',
                      tone: _online ? _Tone.good : _Tone.warn,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(_message),
                  if (_sdMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_sdMessage,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _HealthPanel(
              snapshot: snapshot,
              connection: _online
                  ? ConnectionStateKind.connected
                  : ConnectionStateKind.offline,
            ),
            const SizedBox(height: 12),
            _RecordingPanel(
              snapshot: snapshot,
              enabled: _online,
              onSetRecordingChannels: _setChannels,
            ),
            const SizedBox(height: 12),
            _QuickActionsPanel(
              onRefresh: ({bool silent = false}) async => _refresh(),
              onReconnectWifi: _reconnectWifi,
              onRestartDevice: _restartDevice,
              onSoftwareUpdate: _openSoftwareUpdate,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionChoiceCard extends StatelessWidget {
  const _ConnectionChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key, this.provisioning = false});

  final bool provisioning;

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  final List<ScanResult> _devices = <ScanResult>[];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _scanning = false;
  String _message = 'Ready to scan for MotemaSens devices.';

  @override
  void initState() {
    super.initState();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where(_isMotemaDevice).toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      if (mounted) {
        setState(() {
          _devices
            ..clear()
            ..addAll(filtered);
        });
      }
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  bool _isMotemaDevice(ScanResult result) {
    final name = _bleName(result);
    return name.startsWith('MotemaSens') ||
        result.advertisementData.serviceUuids.contains(motemaBleServiceUuid);
  }

  String _bleName(ScanResult result) {
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    if (result.device.advName.isNotEmpty) {
      return result.device.advName;
    }
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    }
    return result.device.remoteId.str;
  }

  int _bleSerial(ScanResult result) {
    final match = RegExp(r'ms-(\d{1,4})').firstMatch(_bleName(result));
    return match == null ? 0 : int.tryParse(match.group(1) ?? '') ?? 0;
  }

  String _bleTitle(ScanResult result) {
    final serial = _bleSerial(result);
    if (serial > 0) {
      return 'MotemaSens Serial #${serial.toString().padLeft(3, '0')}';
    }
    return _bleName(result);
  }

  Future<bool> _ensureBlePermissions() async {
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> _startScan() async {
    if (!await _ensureBlePermissions()) {
      setState(() => _message = 'Bluetooth permissions are required.');
      return;
    }
    setState(() {
      _scanning = true;
      _message = 'Scanning...';
      _devices.clear();
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        androidScanMode: AndroidScanMode.lowLatency,
      );
      final latest = FlutterBluePlus.lastScanResults
          .where(_isMotemaDevice)
          .toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      setState(() {
        _devices
          ..clear()
          ..addAll(latest);
        _message = latest.isEmpty
            ? 'No MotemaSens BLE devices found.'
            : 'Select a MotemaSens device.';
      });
    } catch (error) {
      setState(() => _message = 'BLE scan failed: $error');
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _openDevice(ScanResult result) async {
    await FlutterBluePlus.stopScan();
    if (!mounted) {
      return;
    }
    final client = BleDeviceClient(result.device);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => widget.provisioning
            ? WifiProvisioningScreen(client: client)
            : BleDeviceDashboardScreen(client: client),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              Text(widget.provisioning ? 'Provision Device' : 'BLE Control')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.bluetooth_searching,
                  title: widget.provisioning
                      ? 'Find device for WiFi setup'
                      : 'Find MotemaSens device',
                  trailing: _StatusPill(
                    label: _scanning ? 'Scanning' : 'BLE',
                    tone: _scanning ? _Tone.warn : _Tone.good,
                  ),
                ),
                const SizedBox(height: 12),
                Text(_message),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon: const Icon(Icons.radar),
                  label: Text(_scanning ? 'Scanning...' : 'Scan'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final result in _devices)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                leading: const Icon(Icons.bluetooth_connected),
                title: Text(_bleTitle(result)),
                subtitle: Text(
                    '${_bleName(result)}\n${result.device.remoteId.str}  RSSI ${result.rssi}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDevice(result),
              ),
            ),
        ],
      ),
    );
  }
}

class BleDeviceDashboardScreen extends StatefulWidget {
  const BleDeviceDashboardScreen({super.key, required this.client});

  final BleDeviceClient client;

  @override
  State<BleDeviceDashboardScreen> createState() =>
      _BleDeviceDashboardScreenState();
}

class _BleDeviceDashboardScreenState extends State<BleDeviceDashboardScreen> {
  DeviceSnapshot _snapshot = DeviceSnapshot.empty();
  ConnectionStateKind _connection = ConnectionStateKind.connecting;
  final List<String> _log = <String>['Connecting over BLE...'];
  bool _commandBusy = false;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _connectionSubscription =
        widget.client.connectionState.listen(_handleConnectionState);
    _connect();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    widget.client.disconnect();
    super.dispose();
  }

  void _handleConnectionState(BluetoothConnectionState state) {
    if (!mounted || state == BluetoothConnectionState.connected) {
      return;
    }
    if (_connection == ConnectionStateKind.connecting) {
      return;
    }
    if (_connection == ConnectionStateKind.offline && !_commandBusy) {
      return;
    }
    setState(() {
      _connection = ConnectionStateKind.offline;
      _commandBusy = false;
    });
    _addLog('BLE disconnected.');
  }

  void _addLog(String message) {
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $message');
      if (_log.length > 30) {
        _log.removeLast();
      }
    });
  }

  Future<void> _connect() async {
    try {
      await widget.client.connect();
      final snapshot = await widget.client.readStatus();
      setState(() {
        _snapshot = snapshot;
        _connection = ConnectionStateKind.connected;
      });
      _addLog('Connected to ${widget.client.displayName}');
    } catch (error) {
      setState(() => _connection = ConnectionStateKind.offline);
      _addLog('BLE connect failed: $error');
    }
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await widget.client.readStatus();
      setState(() => _snapshot = snapshot);
      _addLog('BLE status refreshed.');
    } catch (error) {
      _addLog('BLE status failed: $error');
    }
  }

  Future<bool> _command(Map<String, Object?> command, String label) async {
    if (_commandBusy) {
      _addLog('$label ignored, command already running.');
      return false;
    }
    if (_connection != ConnectionStateKind.connected ||
        !await widget.client.isConnected) {
      setState(() => _connection = ConnectionStateKind.offline);
      _addLog('$label ignored, BLE is not connected.');
      return false;
    }
    setState(() => _commandBusy = true);
    try {
      await widget.client.sendCommand(command);
      _addLog('$label sent.');
      await _refresh();
      return true;
    } catch (error) {
      _addLog('$label failed: $error');
      return false;
    } finally {
      if (mounted) {
        setState(() => _commandBusy = false);
      }
    }
  }

  Future<void> _setRecordingChannels(Set<LoggingChannel> channels) async {
    if (_commandBusy) {
      _addLog('${_channelsLabel(channels)} ignored, command already running.');
      return;
    }
    if (_snapshot.loggingChannels.length == channels.length &&
        _snapshot.loggingChannels.containsAll(channels)) {
      _addLog('${_channelsLabel(channels)} already active.');
      return;
    }
    await _command({
      'command': 'set_recording_channels',
      'ecg': channels.contains(LoggingChannel.ecg),
      'mic': channels.contains(LoggingChannel.mic),
      'imu': channels.contains(LoggingChannel.imu),
    }, '${_channelsLabel(channels)} command');
  }

  Future<void> _restartDevice() async {
    if (_commandBusy) {
      _addLog('Restart ignored, command already running.');
      return;
    }
    if (_connection != ConnectionStateKind.connected ||
        !await widget.client.isConnected) {
      setState(() => _connection = ConnectionStateKind.offline);
      _addLog('Restart ignored, BLE is not connected.');
      return;
    }
    setState(() => _commandBusy = true);
    try {
      await widget.client.sendCommand({'command': 'restart_device'});
      _addLog('Restart command sent. Wait for the ESP32 to boot.');
      if (mounted) {
        setState(() => _connection = ConnectionStateKind.offline);
      }
    } catch (error) {
      _addLog('Restart failed: $error');
    } finally {
      if (mounted) {
        setState(() => _commandBusy = false);
      }
    }
  }

  String _channelsLabel(Set<LoggingChannel> channels) {
    if (channels.isEmpty) return 'Stop';
    final labels = [
      if (channels.contains(LoggingChannel.ecg)) 'ECG',
      if (channels.contains(LoggingChannel.mic)) 'MIC',
      if (channels.contains(LoggingChannel.imu)) 'IMU',
    ];
    return labels.join(' + ');
  }

  void _openBleSoftwareUpdate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftwareUpdateScreen(
          method: OtaMethod.ble,
          currentVersion: _snapshot.version,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Device Control')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HealthPanel(snapshot: _snapshot, connection: _connection),
          const SizedBox(height: 12),
          _RecordingPanel(
            snapshot: _snapshot,
            onSetRecordingChannels: _setRecordingChannels,
            enabled:
                !_commandBusy && _connection == ConnectionStateKind.connected,
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                    icon: Icons.bluetooth_connected, title: 'BLE controls'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _commandBusy ? null : _refresh,
                        icon: const Icon(Icons.sync),
                        label: const Text('Read status'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _openBleSoftwareUpdate,
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('Software Update'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _commandBusy
                            ? null
                            : () => _command(
                                  {'command': 'reconnect_wifi'},
                                  'Reconnect WiFi',
                                ),
                        icon: const Icon(Icons.wifi_find),
                        label: const Text('Reconnect WiFi'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _commandBusy ? null : _restartDevice,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Restart ESP32'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _commandBusy
                            ? null
                            : () => _command(
                                  {'command': 'start_usb_log'},
                                  'Start USB log',
                                ),
                        icon: const Icon(Icons.fiber_manual_record),
                        label: const Text('Start USB log'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _commandBusy
                            ? null
                            : () => _command(
                                  {'command': 'stop_usb_log'},
                                  'Stop USB log',
                                ),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop USB log'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InlineLogPanel(events: _log),
        ],
      ),
    );
  }
}

class DeveloperPasswordScreen extends StatefulWidget {
  const DeveloperPasswordScreen({super.key});

  @override
  State<DeveloperPasswordScreen> createState() =>
      _DeveloperPasswordScreenState();
}

class _DeveloperPasswordScreenState extends State<DeveloperPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  String _message = 'Enter developer password.';

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _continue() {
    if (_passwordController.text == developerPassword) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => const BleScanScreen(provisioning: true)),
      );
    } else {
      setState(() => _message = 'Wrong password.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Access')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                    icon: Icons.lock_outline, title: 'Developer access'),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Developer password',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _continue(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _continue,
                  icon: const Icon(Icons.login),
                  label: const Text('Continue'),
                ),
                const SizedBox(height: 8),
                Text(_message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WifiProvisioningScreen extends StatefulWidget {
  const WifiProvisioningScreen({super.key, required this.client});

  final BleDeviceClient client;

  @override
  State<WifiProvisioningScreen> createState() => _WifiProvisioningScreenState();
}

class _WifiProvisioningScreenState extends State<WifiProvisioningScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _message = 'Connect over BLE, then send WiFi credentials.';
  String _ipAddress = '';
  bool _busy = false;
  bool _ledsOffOverride = false;

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _provision() async {
    setState(() {
      _busy = true;
      _message = 'Sending WiFi credentials...';
      _ipAddress = '';
    });
    try {
      if (!await widget.client.isConnected) {
        await widget.client.connect();
      }
      final result = await widget.client.provisionWifi(
        ssid: _ssidController.text.trim(),
        password: _passwordController.text,
      );
      final connected = result['wifiConnected'] == true;
      final ip = (result['ipAddress'] as String?) ?? '';
      setState(() {
        _message = connected
            ? 'WiFi connected. IP $ip'
            : ((result['message'] as String?) ?? 'WiFi connect failed.');
        _ipAddress = ip;
      });
    } catch (error) {
      setState(() => _message = 'Provisioning failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _busy = true;
      _message = 'Reading BLE status...';
    });
    try {
      if (!await widget.client.isConnected) {
        await widget.client.connect();
      }
      final snapshot = await widget.client.readStatus();
      setState(() {
        _ledsOffOverride = snapshot.ledsOffOverride;
        _ipAddress = snapshot.ip;
        _message = snapshot.ip.isEmpty
            ? 'BLE connected. WiFi is not connected.'
            : 'BLE connected. IP ${snapshot.ip}';
      });
    } catch (error) {
      setState(() => _message = 'BLE status failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setLedOffOverride(bool enabled) async {
    setState(() {
      _busy = true;
      _message = enabled ? 'Turning all LEDs off...' : 'Restoring LED mode...';
    });
    try {
      if (!await widget.client.isConnected) {
        await widget.client.connect();
      }
      await widget.client.setLedOffOverride(enabled);
      final snapshot = await widget.client.readStatus();
      setState(() {
        _ledsOffOverride = snapshot.ledsOffOverride;
        _message = enabled
            ? 'All LEDs forced off. This also overrides logging LED.'
            : 'LED override cleared.';
      });
    } catch (error) {
      setState(() => _message = 'LED override failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runSelfTest() async {
    setState(() {
      _busy = true;
      _message = 'Starting self-test...';
    });
    try {
      if (!await widget.client.isConnected) {
        await widget.client.connect();
      }
      await widget.client.sendCommand({'command': 'self_test'});
      setState(() {
        _ledsOffOverride = false;
        _message = 'Self-test started.';
      });
    } catch (error) {
      setState(() => _message = 'Self-test failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openLocal() {
    if (_ipAddress.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalDeviceDashboardScreen(
          initialBaseUrl: 'http://$_ipAddress',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Device')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Debug access'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _refreshStatus,
                  icon: const Icon(Icons.bluetooth_connected),
                  label: const Text('Connect and read status'),
                ),
                const SizedBox(height: 8),
                Text(_message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                    icon: Icons.wifi_password, title: 'WiFi setup over BLE'),
                const SizedBox(height: 12),
                TextField(
                  controller: _ssidController,
                  decoration: const InputDecoration(
                    labelText: 'WiFi SSID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'WiFi password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _provision,
                  icon: const Icon(Icons.save),
                  label: Text(_busy ? 'Connecting...' : 'Save and connect'),
                ),
                if (_ipAddress.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openLocal,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Open Local mode'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                    icon: Icons.lightbulb_outline, title: 'LED override'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _ledsOffOverride,
                  onChanged: _busy ? null : _setLedOffOverride,
                  title: const Text('Force all LEDs off'),
                  subtitle: const Text(
                      'Overrides heartbeat, manual LEDs and logging indicator.'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _runSelfTest,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Run LED self-test'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LocalConnectScreen extends StatelessWidget {
  const LocalConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LocalDeviceDashboardScreen();
  }
}

class LocalDeviceDashboardScreen extends DeviceControllerScreen {
  const LocalDeviceDashboardScreen({super.key, super.initialBaseUrl});
}

class DeviceControllerScreen extends StatefulWidget {
  const DeviceControllerScreen({super.key, this.initialBaseUrl});

  final String? initialBaseUrl;

  @override
  State<DeviceControllerScreen> createState() => _DeviceControllerScreenState();
}

class _DeviceControllerScreenState extends State<DeviceControllerScreen> {
  late final TextEditingController _baseUrlController = TextEditingController(
      text: widget.initialBaseUrl ?? 'http://192.168.5.29');
  final List<String> _events = <String>[
    'Ready. Connect to your MotemaSens device.'
  ];
  final List<double> _ecgSamples = <double>[
    0.12,
    0.16,
    0.09,
    0.42,
    -0.18,
    0.04,
    0.11,
    0.08,
    0.35,
    -0.12
  ];
  final List<double> _micSamples = List<double>.filled(180, 0);
  final List<double> _imuSamples = List<double>.filled(180, 0);

  DeviceSnapshot _snapshot = DeviceSnapshot.empty();
  ConnectionStateKind _connection = ConnectionStateKind.offline;
  int _tabIndex = 0;
  Timer? _pollTimer;
  Timer? _livePaintTimer;
  Timer? _livePollTimer;
  DeviceApi? _api;
  bool _liveStreaming = false;
  String _liveMessage = 'Live stream idle';
  int _liveSamples = 0;
  String _streamHealth = 'Stream status idle';
  double _ecgBaseline = 0;
  double _ecgScale = 90000;
  double _micPeak = 0.05;
  List<SdLogFile> _sdFiles = const [];
  bool _sdLoading = false;
  String _sdMessage = 'Connect by IP to browse SD logs.';

  @override
  void dispose() {
    _pollTimer?.cancel();
    _livePaintTimer?.cancel();
    _livePollTimer?.cancel();
    _baseUrlController.dispose();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _events.insert(0, '${TimeOfDay.now().format(context)}  $message');
      if (_events.length > 40) {
        _events.removeLast();
      }
    });
  }

  Future<void> _connect() async {
    final baseUrl =
        _baseUrlController.text.trim().replaceAll(RegExp(r'/$'), '');
    setState(() {
      _connection = ConnectionStateKind.connecting;
      _api = DeviceApi(baseUrl: baseUrl);
    });
    try {
      final snapshot = await _api!.fetchStatus();
      setState(() {
        _snapshot = snapshot;
        _connection = ConnectionStateKind.connected;
      });
      _log('Connected to $baseUrl');
      _startPolling();
      await _refreshSdFiles(silent: true);
    } catch (error) {
      setState(() {
        _connection = ConnectionStateKind.offline;
      });
      _log('Device not reachable. Check IP address and WiFi.');
    }
  }

  void _disconnect() {
    _pollTimer?.cancel();
    _stopLiveStream(sendStop: true);
    setState(() {
      _connection = ConnectionStateKind.offline;
    });
    _log('Disconnected.');
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 4), (_) => _refreshStatus(silent: true));
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    if (_connection != ConnectionStateKind.connected || _api == null) {
      if (!silent) {
        _log('Connect to the device before refreshing status.');
      }
      return;
    }

    try {
      final snapshot = await _api!.fetchStatus();
      setState(() {
        _snapshot = snapshot;
      });
      if (!silent) {
        _log('Status refreshed.');
      }
      if (snapshot.sdReady && _sdFiles.isEmpty) {
        await _refreshSdFiles(silent: true);
      }
    } catch (error) {
      setState(() {
        _connection = ConnectionStateKind.offline;
      });
      _log('Connection lost. Device is offline.');
    }
  }

  Future<void> _reconnectWifi() async {
    if (_connection != ConnectionStateKind.connected || _api == null) {
      _log('Connect by local IP before asking ESP32 to reconnect WiFi.');
      return;
    }
    try {
      await _api!.reconnectWifi();
      _log('WiFi reconnect command sent.');
      await Future<void>.delayed(const Duration(seconds: 2));
      await _refreshStatus(silent: true);
    } catch (error) {
      _log('WiFi reconnect failed: $error');
    }
  }

  Future<void> _restartDevice() async {
    if (_connection != ConnectionStateKind.connected || _api == null) {
      _log('Connect by local IP before restarting ESP32.');
      return;
    }
    try {
      await _api!.restartDevice();
      _pollTimer?.cancel();
      _log('Restart command sent. Reconnect after the ESP32 boots.');
      setState(() => _connection = ConnectionStateKind.offline);
    } catch (error) {
      _log('Restart command failed: $error');
    }
  }

  Future<void> _setRecordingChannels(Set<LoggingChannel> channels) async {
    final mode = channels.isEmpty
        ? RecordingMode.idle
        : channels.length == 3
            ? RecordingMode.all
            : RecordingMode.mixed;
    setState(() {
      _snapshot = _snapshot.copyWith(
        recordingMode: mode,
        logEcg: channels.contains(LoggingChannel.ecg),
        logMic: channels.contains(LoggingChannel.mic),
        logImu: channels.contains(LoggingChannel.imu),
        lastSeen: DateTime.now(),
      );
      _ecgSamples
        ..removeAt(0)
        ..add(channels.contains(LoggingChannel.ecg) ? 0.28 : 0.05);
    });

    if (_connection == ConnectionStateKind.connected && _api != null) {
      try {
        await _api!.setRecordingChannels(channels);
        _log('${_channelsLabel(channels)} command sent.');
        if (channels.isEmpty && _liveStreaming) {
          await _stopLiveStream(sendStop: false);
        }
      } catch (error) {
        _log('Recording command failed. Check firmware endpoint.');
      }
    } else {
      _log('Connect to the device before changing recording channels.');
    }
  }

  Future<void> _toggleLiveStream() async {
    if (_liveStreaming) {
      await _stopLiveStream(sendStop: true);
      return;
    }
    await _startLiveStream();
  }

  Future<void> _startLiveStream() async {
    if (_connection != ConnectionStateKind.connected || _api == null) {
      _log('Connecting before live view.');
      await _connect();
      if (_connection != ConnectionStateKind.connected || _api == null) {
        setState(() => _liveMessage = 'Connect to ESP32 first');
        return;
      }
    }

    await _stopLiveStream(sendStop: false);
    setState(() {
      _liveStreaming = true;
      _liveMessage = 'Starting live view...';
      _liveSamples = 0;
    });

    _livePaintTimer?.cancel();
    _livePaintTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted && _liveStreaming) {
        setState(() {});
      }
    });

    try {
      await _api!.setRecording(RecordingMode.ecg);
      final first = await _api!.fetchStatus();
      _appendLiveSnapshot(first);
      setState(() => _snapshot = first);
      _livePollTimer = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => _pollLiveSample(),
      );
      _log('Live waveform view started.');
      setState(() => _liveMessage = 'Live stream running');
    } catch (error) {
      _livePaintTimer?.cancel();
      if (mounted) {
        setState(() {
          _liveStreaming = false;
          _liveMessage = 'Live stream failed';
        });
      }
      _log('Live stream failed. Check ESP32 WiFi.');
    }
  }

  Future<void> _stopLiveStream({required bool sendStop}) async {
    _livePaintTimer?.cancel();
    _livePaintTimer = null;
    _livePollTimer?.cancel();
    _livePollTimer = null;
    final wasStreaming = _liveStreaming;
    if (mounted) {
      setState(() {
        _liveStreaming = false;
        _liveMessage = 'Live stream stopped';
      });
    }
    if (sendStop && wasStreaming && _api != null) {
      try {
        await _api!.setRecording(RecordingMode.idle);
      } catch (_) {
        // The stream may already have closed on the ESP32 side.
      }
    }
  }

  Future<void> _pollLiveSample() async {
    if (!_liveStreaming || _api == null) {
      return;
    }
    try {
      final snapshot = await _api!.fetchStatus();
      final streamStatus = await _api!.fetchStreamStatus();
      _appendLiveSnapshot(snapshot);
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _streamHealth =
              'stream rows ${streamStatus['rows'] ?? 0}, disconnects ${streamStatus['disconnects'] ?? 0}';
          _liveMessage = 'Live stream running';
        });
      }
    } catch (_) {
      _livePollTimer?.cancel();
      _livePaintTimer?.cancel();
      if (mounted) {
        setState(() {
          _liveStreaming = false;
          _liveMessage = 'Live stream stopped';
        });
      }
      _log('Live view stopped. ESP32 status not reachable.');
    }
  }

  void _appendLiveSnapshot(DeviceSnapshot snapshot) {
    final mic = snapshot.micTrace.clamp(-1.0, 1.0);
    _micPeak = math.max(0.02, (_micPeak * 0.985) + (mic.abs() * 0.015));
    _appendBounded(
      _micSamples,
      (mic / math.max(_micPeak, 0.04)).clamp(-1.0, 1.0),
    );

    final ecgRaw = snapshot.ecgCh1 - snapshot.ecgCh2;
    _ecgBaseline += (ecgRaw - _ecgBaseline) * 0.006;
    final ecgFiltered = ecgRaw - _ecgBaseline;
    _ecgScale =
        math.max(30000, (_ecgScale * 0.992) + (ecgFiltered.abs() * 0.008));
    _appendBounded(
      _ecgSamples,
      (ecgFiltered / _ecgScale).clamp(-1.0, 1.0),
    );

    final imuMagnitude = math.sqrt(
      (snapshot.accX * snapshot.accX) +
          (snapshot.accY * snapshot.accY) +
          (snapshot.accZ * snapshot.accZ),
    );
    _appendBounded(_imuSamples, ((imuMagnitude - 1.0) * 4.0).clamp(-1.0, 1.0));
    ++_liveSamples;
  }

  void _appendBounded(List<double> samples, double value) {
    if (samples.length >= 180) {
      samples.removeAt(0);
    }
    samples.add(value);
  }

  Future<void> _refreshSdFiles({bool silent = false}) async {
    if (_api == null || _connection != ConnectionStateKind.connected) {
      setState(() {
        _sdFiles = const [];
        _sdMessage = 'Connect by IP to browse SD logs.';
      });
      if (!silent) {
        _log('SD browser needs local IP connection.');
      }
      return;
    }

    setState(() {
      _sdLoading = true;
      _sdMessage = 'Reading SD file list...';
    });

    try {
      final files = await _api!.fetchSdFiles();
      setState(() {
        _sdFiles = files;
        _sdMessage = files.isEmpty
            ? 'No SD logs found yet.'
            : '${files.length} SD log files found.';
      });
      if (!silent) {
        _log('SD file list refreshed.');
      }
    } catch (error) {
      setState(() => _sdMessage = 'SD list failed: $error');
      if (!silent) {
        _log('SD file list failed.');
      }
    } finally {
      if (mounted) {
        setState(() => _sdLoading = false);
      }
    }
  }

  Future<void> _previewSdFile(SdLogFile file) async {
    if (_api == null) {
      _log('Connect by IP to preview SD files.');
      return;
    }
    try {
      final preview = await _api!.fetchSdFileCsvPreview(file.name);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${file.name} CSV preview'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      _log('Converted preview for ${file.name}.');
    } catch (_) {
      _log('SD preview failed.');
    }
  }

  Future<void> _copySdDownloadLink(SdLogFile file) async {
    if (_api == null) {
      _log('Connect by IP to copy SD download links.');
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: _api!.sdFileUri(file.name).toString()),
    );
    _log('Copied SD download link for ${file.name}.');
  }

  Future<void> _downloadSdFile(SdLogFile file) async {
    if (_api == null) {
      _log('Connect by IP to download SD files.');
      return;
    }
    setState(() => _sdMessage = 'Downloading ${file.name} to phone...');
    try {
      final bytes = await _api!.fetchSdFileBytes(file.name);
      await downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        {
          'fileName': file.name,
          'bytes': bytes,
          'mimeType': file.name.toLowerCase().endsWith('.csv')
              ? 'text/csv'
              : 'application/octet-stream',
        },
      );
      setState(() => _sdMessage = 'Downloaded ${file.name} to Downloads.');
      _log('Downloaded ${file.name} to phone.');
    } catch (error) {
      setState(() => _sdMessage = 'Download failed: $error');
      _log('SD download failed.');
    }
  }

  String _channelsLabel(Set<LoggingChannel> channels) {
    if (channels.isEmpty) return 'Idle';
    final labels = [
      if (channels.contains(LoggingChannel.ecg)) 'ECG',
      if (channels.contains(LoggingChannel.mic)) 'MIC',
      if (channels.contains(LoggingChannel.imu)) 'IMU',
    ];
    return '${labels.join(' + ')} logging';
  }

  void _openSoftwareUpdate() {
    final api = _api;
    if (api == null || _connection != ConnectionStateKind.connected) {
      _log('Connect by IP before software update.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SoftwareUpdateScreen(
          method: OtaMethod.localWifi,
          currentVersion: _snapshot.version,
          localApi: api,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardView(
        snapshot: _snapshot,
        connection: _connection,
        baseUrlController: _baseUrlController,
        ecgSamples: _ecgSamples,
        onConnect: _connect,
        onDisconnect: _disconnect,
        onRefresh: _refreshStatus,
        onReconnectWifi: _reconnectWifi,
        onRestartDevice: _restartDevice,
        onSoftwareUpdate: _openSoftwareUpdate,
        onSetRecordingChannels: _setRecordingChannels,
      ),
      _TelemetryView(
        snapshot: _snapshot,
        connection: _connection,
        ecgSamples: _ecgSamples,
        micSamples: _micSamples,
        imuSamples: _imuSamples,
        liveStreaming: _liveStreaming,
        liveMessage: _liveMessage,
        streamHealth: _streamHealth,
        liveSamples: _liveSamples,
        onToggleLive: _toggleLiveStream,
      ),
      _StorageView(
        snapshot: _snapshot,
        files: _sdFiles,
        loading: _sdLoading,
        message: _sdMessage,
        ipConnected: _connection == ConnectionStateKind.connected,
        onRefresh: _refreshSdFiles,
        onPreview: _previewSdFile,
        onDownload: _downloadSdFile,
        onCopyLink: _copySdDownloadLink,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local IP Control'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _refreshStatus(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Control'),
          NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart),
              label: 'Signals'),
          NavigationDestination(
              icon: Icon(Icons.sd_storage_outlined),
              selectedIcon: Icon(Icons.sd_storage),
              label: 'Storage'),
        ],
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.snapshot,
    required this.connection,
    required this.baseUrlController,
    required this.ecgSamples,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRefresh,
    required this.onReconnectWifi,
    required this.onRestartDevice,
    required this.onSoftwareUpdate,
    required this.onSetRecordingChannels,
  });

  final DeviceSnapshot snapshot;
  final ConnectionStateKind connection;
  final TextEditingController baseUrlController;
  final List<double> ecgSamples;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Future<void> Function({bool silent}) onRefresh;
  final Future<void> Function() onReconnectWifi;
  final Future<void> Function() onRestartDevice;
  final VoidCallback onSoftwareUpdate;
  final Future<void> Function(Set<LoggingChannel> channels)
      onSetRecordingChannels;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConnectionPanel(
          connection: connection,
          baseUrlController: baseUrlController,
          onConnect: onConnect,
          onDisconnect: onDisconnect,
        ),
        const SizedBox(height: 12),
        _HealthPanel(snapshot: snapshot, connection: connection),
        const SizedBox(height: 12),
        _RecordingPanel(
          snapshot: snapshot,
          onSetRecordingChannels: onSetRecordingChannels,
          enabled: true,
        ),
        const SizedBox(height: 12),
        _QuickActionsPanel(
          onRefresh: onRefresh,
          onReconnectWifi: onReconnectWifi,
          onRestartDevice: onRestartDevice,
          onSoftwareUpdate: onSoftwareUpdate,
        ),
        const SizedBox(height: 12),
        _SafetyPanel(),
      ],
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.connection,
    required this.baseUrlController,
    required this.onConnect,
    required this.onDisconnect,
  });

  final ConnectionStateKind connection;
  final TextEditingController baseUrlController;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final connected = connection == ConnectionStateKind.connected;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.wifi_tethering,
            title: 'Device connection',
            trailing: _StatusPill(
                label: _connectionLabel(connection),
                tone: connected ? _Tone.good : _Tone.warn),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: baseUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'ESP32 base URL',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onConnect,
                  icon: const Icon(Icons.cable),
                  label: Text(connected ? 'Reconnect' : 'Connect'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Disconnect',
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthPanel extends StatelessWidget {
  const _HealthPanel({required this.snapshot, required this.connection});

  final DeviceSnapshot snapshot;
  final ConnectionStateKind connection;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
              icon: Icons.favorite_border, title: 'Device health'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _MetricTile(
                      label: 'Battery',
                      value: _batteryStatusText(
                        snapshot.batteryVolts,
                        snapshot.batterySoc,
                        snapshot.batteryCharging,
                        snapshot.batteryPresent,
                      ),
                      icon: !snapshot.batteryPresent
                          ? Icons.warning_amber_rounded
                          : snapshot.batteryCharging
                              ? Icons.battery_charging_full
                              : Icons.battery_5_bar)),
              const SizedBox(width: 8),
              Expanded(
                  child: _MetricTile(
                      label: 'Signal',
                      value: '${snapshot.signalQuality}%',
                      icon: Icons.show_chart)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _MetricTile(
                      label: 'Sample rate',
                      value: '${snapshot.sampleRate} Hz',
                      icon: Icons.speed)),
              const SizedBox(width: 8),
              Expanded(
                  child: _MetricTile(
                      label: 'microSD',
                      value: snapshot.sdReady
                          ? '${snapshot.sdFreeGb.toStringAsFixed(1)} GB'
                          : 'Not ready',
                      icon: Icons.sd_card)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _MetricTile(
                      label: 'Firmware',
                      value: snapshot.version,
                      icon: Icons.new_releases_outlined)),
              const SizedBox(width: 8),
              Expanded(
                  child: _MetricTile(
                      label: 'WiFi log',
                      value: snapshot.wifiLogging ? 'Running' : 'Stopped',
                      icon: Icons.wifi_tethering)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'IP ${snapshot.ip.isEmpty ? 'not connected' : snapshot.ip}  USB ${snapshot.usbLogging ? 'logging' : 'idle'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({
    required this.snapshot,
    required this.onSetRecordingChannels,
    required this.enabled,
  });

  final DeviceSnapshot snapshot;
  final Future<void> Function(Set<LoggingChannel> channels)
      onSetRecordingChannels;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = snapshot.loggingChannels;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
              icon: Icons.sd_card_outlined, title: 'Write to SD card'),
          const SizedBox(height: 12),
          SegmentedButton<LoggingChannel>(
            multiSelectionEnabled: true,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(
                  value: LoggingChannel.ecg,
                  icon: Icon(Icons.monitor_heart_outlined),
                  label: Text('ECG')),
              ButtonSegment(
                  value: LoggingChannel.mic,
                  icon: Icon(Icons.mic_none),
                  label: Text('MIC')),
              ButtonSegment(
                  value: LoggingChannel.imu,
                  icon: Icon(Icons.screen_rotation_alt_outlined),
                  label: Text('IMU')),
            ],
            selected: selected,
            onSelectionChanged: enabled
                ? (selection) => onSetRecordingChannels(selection)
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled
                      ? () => onSetRecordingChannels({
                            LoggingChannel.ecg,
                            LoggingChannel.mic,
                            LoggingChannel.imu,
                          })
                      : null,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('All'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? () => onSetRecordingChannels({}) : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'SD logging channels: ${_channelText(selected)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _channelText(Set<LoggingChannel> selected) {
    if (selected.isEmpty) return 'Idle';
    final labels = [
      if (selected.contains(LoggingChannel.ecg)) 'ECG',
      if (selected.contains(LoggingChannel.mic)) 'MIC',
      if (selected.contains(LoggingChannel.imu)) 'IMU',
    ];
    return labels.join(' + ');
  }
}

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({
    required this.onRefresh,
    required this.onReconnectWifi,
    required this.onRestartDevice,
    required this.onSoftwareUpdate,
  });

  final Future<void> Function({bool silent}) onRefresh;
  final Future<void> Function() onReconnectWifi;
  final Future<void> Function() onRestartDevice;
  final VoidCallback onSoftwareUpdate;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
              icon: Icons.settings_remote_outlined, title: 'Device actions'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onRefresh(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Refresh'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReconnectWifi,
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('Reconnect WiFi'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onRestartDevice,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Restart ESP32'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onSoftwareUpdate,
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('Software Update'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SafetyPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      color: const Color(0xFFFFFBEB),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.health_and_safety_outlined,
              color: Color(0xFFB45309)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ECG inputs are human-contact hardware. Use test signals during bring-up until isolation, protection, leakage, and regulatory requirements are confirmed.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xFF78350F)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryView extends StatelessWidget {
  const _TelemetryView({
    required this.snapshot,
    required this.connection,
    required this.ecgSamples,
    required this.micSamples,
    required this.imuSamples,
    required this.liveStreaming,
    required this.liveMessage,
    required this.streamHealth,
    required this.liveSamples,
    required this.onToggleLive,
  });

  final DeviceSnapshot snapshot;
  final ConnectionStateKind connection;
  final List<double> ecgSamples;
  final List<double> micSamples;
  final List<double> imuSamples;
  final bool liveStreaming;
  final String liveMessage;
  final String streamHealth;
  final int liveSamples;
  final Future<void> Function() onToggleLive;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(
                icon: Icons.sensors,
                title: 'Live view',
                trailing: _StatusPill(
                  label: liveStreaming ? 'Live' : _connectionLabel(connection),
                  tone: liveStreaming ? _Tone.good : _Tone.warn,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onToggleLive,
                icon: Icon(liveStreaming
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline),
                label:
                    Text(liveStreaming ? 'Stop live view' : 'Start live view'),
              ),
              const SizedBox(height: 8),
              Text(
                '$liveMessage  samples $liveSamples  ${snapshot.ip.isEmpty ? '' : snapshot.ip}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                streamHealth,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _WaveformCard(
          title: 'ECG waveform',
          icon: Icons.monitor_heart_outlined,
          samples: ecgSamples,
          color: const Color(0xFF10B981),
          centerLabel: 'ECG',
          footer: liveStreaming
              ? 'Lead differential, auto scaled'
              : 'Press Start live view to stream ECG',
        ),
        const SizedBox(height: 12),
        _WaveformCard(
          title: 'Microphone waveform',
          icon: Icons.mic_none,
          samples: micSamples,
          color: const Color(0xFF2563EB),
          centerLabel: 'MIC',
          footer: liveStreaming
              ? 'I2S mic trace, auto gain'
              : 'Press Start live view to stream mic',
        ),
        const SizedBox(height: 12),
        _WaveformCard(
          title: 'IMU waveform',
          icon: Icons.screen_rotation_alt_outlined,
          samples: imuSamples,
          color: const Color(0xFFF59E0B),
          centerLabel: 'IMU',
          footer: liveStreaming
              ? 'Acceleration magnitude, gravity removed'
              : 'Press Start live view to stream IMU',
        ),
      ],
    );
  }
}

class _WaveformCard extends StatelessWidget {
  const _WaveformCard({
    required this.title,
    required this.icon,
    required this.samples,
    required this.color,
    required this.centerLabel,
    required this.footer,
  });

  final String title;
  final IconData icon;
  final List<double> samples;
  final Color color;
  final String centerLabel;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: icon, title: title),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _SignalPainter(
                samples,
                color: color,
                centerLabel: centerLabel,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Text(footer, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _StorageView extends StatelessWidget {
  const _StorageView({
    required this.snapshot,
    required this.files,
    required this.loading,
    required this.message,
    required this.ipConnected,
    required this.onRefresh,
    required this.onPreview,
    required this.onDownload,
    required this.onCopyLink,
  });

  final DeviceSnapshot snapshot;
  final List<SdLogFile> files;
  final bool loading;
  final String message;
  final bool ipConnected;
  final Future<void> Function({bool silent}) onRefresh;
  final Future<void> Function(SdLogFile file) onPreview;
  final Future<void> Function(SdLogFile file) onDownload;
  final Future<void> Function(SdLogFile file) onCopyLink;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(
                icon: Icons.sd_storage_outlined,
                title: 'SD logs',
                trailing: _StatusPill(
                  label: snapshot.sdReady ? 'Ready' : 'No SD',
                  tone: snapshot.sdReady ? _Tone.good : _Tone.warn,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'Free space',
                      value: '${snapshot.sdFreeGb.toStringAsFixed(2)} GB',
                      icon: Icons.storage_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(
                      label: 'SD logging',
                      value: snapshot.sdLogging ? 'Running' : 'Stopped',
                      icon: Icons.fiber_smart_record_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.sdPath.isEmpty
                    ? 'Current file: none'
                    : 'Current file: ${snapshot.sdPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Samples ${snapshot.sdSamples}  dropped ${snapshot.sdDropped}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: ipConnected && !loading ? () => onRefresh() : null,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Refresh SD files'),
              ),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!ipConnected)
          const _SectionCard(
            child: Text(
              'Connect by local IP to browse or download SD files. BLE is for control and status only.',
            ),
          )
        else if (files.isEmpty)
          const _SectionCard(child: Text('No files to show.'))
        else
          ...files.map(
            (file) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(file.name),
                  subtitle: Text(file.displaySize),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Convert preview',
                        onPressed: () => onPreview(file),
                        icon: const Icon(Icons.table_view_outlined),
                      ),
                      IconButton(
                        tooltip: 'Download to phone',
                        onPressed: () => onDownload(file),
                        icon: const Icon(Icons.file_download_outlined),
                      ),
                      IconButton(
                        tooltip: 'Copy download link',
                        onPressed: () => onCopyLink(file),
                        icon: const Icon(Icons.link),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _InlineLogPanel extends StatelessWidget {
  const _InlineLogPanel({required this.events});

  final List<String> events;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(icon: Icons.receipt_long_outlined, title: 'Log'),
          const SizedBox(height: 8),
          for (final event in events.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.terminal, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

enum _Tone { good, warn }

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final good = tone == _Tone.good;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: good ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: good ? const Color(0xFF166534) : const Color(0xFF92400E),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 12),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  _SignalPainter(
    this.samples, {
    required this.color,
    required this.centerLabel,
  });

  final List<double> samples;
  final Color color;
  final String centerLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final plotRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final bgPaint = Paint()..color = const Color(0xFF071114);
    canvas.drawRRect(plotRect, bgPaint);

    final gridPaint = Paint()
      ..color = const Color(0x2238BDF8)
      ..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final centerPaint = Paint()
      ..color = const Color(0x55E5E7EB)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    if (samples.length < 2) {
      return;
    }
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final sample = samples[i].clamp(-1.0, 1.0);
      final y = size.height / 2 - sample * size.height * 0.42;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    final labelPainter = TextPainter(
      text: TextSpan(
        text: centerLabel,
        style: const TextStyle(
          color: Color(0x99FFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(10, size.height / 2 + 8));
  }

  @override
  bool shouldRepaint(covariant _SignalPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.color != color ||
        oldDelegate.centerLabel != centerLabel;
  }
}

String _connectionLabel(ConnectionStateKind connection) {
  return switch (connection) {
    ConnectionStateKind.offline => 'Offline',
    ConnectionStateKind.connecting => 'Connecting',
    ConnectionStateKind.connected => 'Connected',
  };
}
