import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motemasens_mobile/main.dart';

void main() {
  test('device snapshot parses battery voltage soc and charging state', () {
    final snapshot = DeviceSnapshot.fromJson({
      'batteryVolts': 2.57,
      'batterySoc': 0,
      'batteryCharging': false,
      'sampleRate': 500,
    });

    expect(snapshot.batteryVolts, 2.57);
    expect(snapshot.batterySoc, 0);
    expect(snapshot.batteryCharging, isFalse);
    expect(snapshot.batteryPresent, isTrue);
  });

  test('device snapshot estimates soc from older voltage-only payloads', () {
    final snapshot = DeviceSnapshot.fromJson({
      'batteryVolts': 4.08,
      'sampleRate': 500,
    });

    expect(snapshot.batteryVolts, 4.08);
    expect(snapshot.batterySoc, inInclusiveRange(80, 90));
  });

  test('device snapshot parses compact ble battery payload', () {
    final snapshot = DeviceSnapshot.fromJson({
      'sn': 1,
      'v': 'dev-2026.06.15.20-ble-battery',
      'rm': 'idle',
      'sr': true,
      'sl': false,
      'fs': 500,
      'lm': 'heartbeat',
      'lo': false,
      'bv': 3.92,
      'bs': 70,
      'bc': true,
    });

    expect(snapshot.deviceSerial, 1);
    expect(snapshot.version, 'dev-2026.06.15.20-ble-battery');
    expect(snapshot.recordingMode, RecordingMode.idle);
    expect(snapshot.sdReady, isTrue);
    expect(snapshot.sdLogging, isFalse);
    expect(snapshot.sampleRate, 500);
    expect(snapshot.ledMode, 'heartbeat');
    expect(snapshot.ledsOffOverride, isFalse);
    expect(snapshot.batteryVolts, 3.92);
    expect(snapshot.batterySoc, 70);
    expect(snapshot.batteryCharging, isTrue);
    expect(snapshot.batteryPresent, isTrue);
  });

  test('device snapshot parses no battery status', () {
    final snapshot = DeviceSnapshot.fromJson({
      'batteryVolts': 2.54,
      'batterySoc': 0,
      'batteryCharging': false,
      'batteryPresent': false,
      'batteryStatus': 'no_battery',
      'sampleRate': 500,
    });

    expect(snapshot.batteryVolts, 2.54);
    expect(snapshot.batterySoc, 0);
    expect(snapshot.batteryCharging, isFalse);
    expect(snapshot.batteryPresent, isFalse);
  });

  test('device snapshot parses compact ble no battery payload', () {
    final snapshot = DeviceSnapshot.fromJson({
      'bv': 2.51,
      'bs': 0,
      'bc': false,
      'bp': false,
      'bst': 'no_battery',
      'fs': 500,
    });

    expect(snapshot.batteryVolts, 2.51);
    expect(snapshot.batterySoc, 0);
    expect(snapshot.batteryCharging, isFalse);
    expect(snapshot.batteryPresent, isFalse);
  });

  testWidgets('opens with the production connection chooser', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(const MotemaSensApp());

    expect(find.text('Connect To MotemaSens'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('BLE'), findsOneWidget);
    expect(find.text('Debug'), findsOneWidget);
    expect(find.textContaining('demo', findRichText: true), findsNothing);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('local option opens the production dashboard', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(const MotemaSensApp());

    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();

    expect(find.text('Local IP Control'), findsOneWidget);
    expect(find.text('Device connection'), findsOneWidget);
    expect(find.text('Control'), findsWidgets);
    expect(find.text('Signals'), findsWidgets);
    expect(find.text('Storage'), findsWidgets);
    expect(find.text('Green LED'), findsNothing);
    expect(find.text('Blue LED'), findsNothing);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('remote login has dev credentials and password toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(const MotemaSensApp());

    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();

    expect(find.text('Remote Login'), findsOneWidget);
    expect(find.text('MotemaSens VPS'), findsOneWidget);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller?.text, defaultRemoteApiBase);
    expect(fields[1].controller?.text, defaultRemoteUsername);
    expect(fields[2].controller?.text, defaultRemotePassword);
    expect(fields[2].obscureText, isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    final visibleFields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(visibleFields[2].obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('ble option opens the normal BLE scan screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(const MotemaSensApp());

    await tester.tap(find.text('BLE'));
    await tester.pumpAndSettle();

    expect(find.text('BLE Control'), findsOneWidget);
    expect(find.text('Find MotemaSens device'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('WiFi setup over BLE'), findsNothing);
    expect(find.text('LED override'), findsNothing);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('debug password gates provisioning tools', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(const MotemaSensApp());

    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();
    expect(find.text('Debug Access'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Provision Device'), findsOneWidget);
    expect(find.text('Find device for WiFi setup'), findsOneWidget);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
