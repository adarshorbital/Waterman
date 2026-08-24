import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/pump_status.dart';

/// Must match the ESP32-S3 firmware exactly.
const String kDeviceName = "WaterMan-V2";
final Guid kServiceUuid = Guid("4fafc201-1fb5-459e-8fcc-c5c9c331914c");
final Guid kControlCharUuid = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a9");
final Guid kStatusCharUuid = Guid("beb5483e-36e1-4688-b7f5-ea07361b26aa");

/// Hard cap mirrored from firmware (firmware enforces its own copy independently;
/// this is only used to clamp the UI so we don't request more than the device allows).
const int kMaxRunSeconds = 180;

enum BleConnState { disconnected, scanning, connecting, connected }

class BleService extends ChangeNotifier {
  BleService._();
  static final BleService instance = BleService._();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _controlChar;
  BluetoothCharacteristic? _statusChar;
  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  BleConnState state = BleConnState.disconnected;
  PumpStatus status = PumpStatus.unknown();
  String? lastError;

  Future<void> scanAndConnect() async {
    lastError = null;
    state = BleConnState.scanning;
    notifyListeners();

    try {
      // Android 12+ requires these granted at RUNTIME, not just declared in
      // the manifest. This was missing entirely — the actual cause of the
      // "bluetooth_scan required" error.
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse, // some OEMs (Samsung included) still gate BLE scan behind this
      ].request();

      final anyDenied = statuses.values.any((s) => !s.isGranted);
      if (anyDenied) {
        lastError = "Bluetooth permission denied. If you tapped 'Deny', "
            "enable it manually: phone Settings > Apps > waterman_app > Permissions.";
        state = BleConnState.disconnected;
        notifyListeners();
        return;
      }

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

      BluetoothDevice? found;
      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          if (r.device.platformName == kDeviceName ||
              r.advertisementData.advName == kDeviceName) {
            found = r.device;
            break;
          }
        }
        if (found != null) break;
      }
      await FlutterBluePlus.stopScan();

      if (found == null) {
        lastError = "WaterMan-V2 not found. Make sure it's powered on and nearby.";
        state = BleConnState.disconnected;
        notifyListeners();
        return;
      }

      _device = found;
      state = BleConnState.connecting;
      notifyListeners();

      // On a device's very first bond with the secured firmware, Android's
      // connect() resolves on the initial GATT connect, then the OS tears
      // that connection down immediately to run bonding (the characteristics
      // require an encrypted, authenticated link) before reconnecting. That
      // makes discoverServices() below throw on this first attempt — retry
      // the whole connect+setup sequence rather than treating it as fatal.
      const maxAttempts = 4;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await _connectAndSetup();
          break;
        } catch (e) {
          if (attempt == maxAttempts) rethrow;
          await Future.delayed(const Duration(seconds: 3));
        }
      }

      state = BleConnState.connected;
      notifyListeners();

      // Sync phone time immediately on connect. On this device's very first
      // pairing with V4 firmware, this write can race the native OS pairing
      // dialog (the characteristic now requires an encrypted, bonded link) —
      // retry rather than treating that as a hard connection failure.
      try {
        await syncTime();
        await requestStatus();
      } catch (e) {
        lastError = "Connected, but pairing may still be finishing — "
            "if this is the first time, approve the Bluetooth pairing prompt "
            "then tap Connect again.";
        notifyListeners();
      }
    } catch (e) {
      lastError = "Connection failed: $e";
      state = BleConnState.disconnected;
      notifyListeners();
    }
  }

  Future<void> _connectAndSetup() async {
    await _device!.connect(timeout: const Duration(seconds: 10));

    await _connSub?.cancel();
    _connSub = _device!.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        state = BleConnState.disconnected;
        notifyListeners();
      }
    });

    final services = await _device!.discoverServices();
    final svc = services.firstWhere((s) => s.uuid == kServiceUuid);
    _controlChar = svc.characteristics.firstWhere((c) => c.uuid == kControlCharUuid);
    _statusChar = svc.characteristics.firstWhere((c) => c.uuid == kStatusCharUuid);

    await _statusChar!.setNotifyValue(true);
    await _statusSub?.cancel();
    _statusSub = _statusChar!.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      status = PumpStatus.fromRaw(utf8.decode(bytes));
      notifyListeners();
    });
  }

  Future<void> disconnect() async {
    await _statusSub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    state = BleConnState.disconnected;
    notifyListeners();
  }

  Future<void> _send(String command) async {
    if (_controlChar == null) return;
    await _controlChar!.write(utf8.encode(command), withoutResponse: false);
  }

  /// Retries a send a couple times with a short delay. Used for the first
  /// commands sent right after connecting, which can race against the native
  /// OS pairing dialog on a device's very first bond (firmware now requires
  /// an encrypted, authenticated link — see WaterMan_V4_secured.ino).
  Future<void> _sendWithRetry(String command,
      {int retries = 3, Duration delay = const Duration(seconds: 2)}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        await _send(command);
        return;
      } catch (e) {
        if (attempt == retries) rethrow;
        await Future.delayed(delay);
      }
    }
  }

  // ---- Public commands ----

  Future<void> pumpOn() => _send("ON");
  Future<void> pumpOff() => _send("OFF");

  Future<void> runFor(int seconds) {
    final clamped = seconds.clamp(1, kMaxRunSeconds);
    return _send("RUN:$clamped");
  }

  Future<void> setSchedule(int hour, int minute, int durationSec) {
    final clamped = durationSec.clamp(1, kMaxRunSeconds);
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    return _send("SCHED:SET:$hh:$mm:$clamped");
  }

  Future<void> clearSchedule() => _send("SCHED:CLEAR");

  Future<void> requestStatus() => _sendWithRetry("STATUS?");

  Future<void> syncTime() {
    final epoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return _sendWithRetry("TIME:$epoch");
  }
}
