// ble_service.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService extends ChangeNotifier {
  // ⚠️ CRITICAL: Must match your ESP32's MAC address exactly
  static const String HARDCODED_DEVICE_ID = "A0:A3:B3:AA:FD:66";

  // ⚠️ CRITICAL: UUIDs MUST match the ESP32 sketch
  static const String SERVICE_UUID = "96f30d22-26f5-4673-a4f6-7b4431e7c5b6";
  static const String DISTANCE_CHAR_UUID = "96f30d22-26f5-4673-a4f6-7b4431e7c5b7";
  static const String SETTINGS_CHAR_UUID = "96f30d22-26f5-4673-a4f6-7b4431e7c5b8";

  // --- Instance Variables ---
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? distanceChar;
  BluetoothCharacteristic? settingsChar;
  bool scanning = false;
  List<ScanResult> scanResults = [];
  double? leftCm;
  double? centerCm;
  double? rightCm;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSub;

  // Singleton
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  bool get isConnected => connectedDevice != null;

  // --- Permission Handling ---
  Future<bool> _checkAndRequestPermissions() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true &&
        statuses[Permission.location]?.isGranted == true;

    if (!allGranted) {
      print("⚠️ Permissions denied: $statuses");
    }

    return allGranted;
  }

  // --- Scanning Methods ---
  void startScan() async {
    if (!(await _checkAndRequestPermissions())) return;

    if (scanning) return;
    scanning = true;
    scanResults.clear();
    notifyListeners();

    FlutterBluePlus.scanResults.listen((results) {
      for (var result in results) {
        if (!scanResults.any((r) => r.device.remoteId == result.device.remoteId)) {
          scanResults.add(result);
          notifyListeners();
        }
      }
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5)).whenComplete(() {
      scanning = false;
      notifyListeners();
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    scanning = false;
    notifyListeners();
  }

  // --- Connection Methods ---
  Future<void> connect(BluetoothDevice device) async {
    if (isConnected) await disconnect();

    try {
      print("Attempting to connect to: ${device.remoteId.str}");

      // Retry logic for release mode
      int retries = 2;
      bool connected = false;
      while (retries > 0 && !connected) {
        try {
          await device.connect(
            timeout: const Duration(seconds: 15),
            autoConnect: false,
            license: License.free,
          );
          connected = true;
        } catch (e) {
          print("⚠️ Connect attempt failed: $e");
          retries--;
          if (retries > 0) await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (!connected) throw Exception("Could not connect after retries");

      connectedDevice = device;

      _deviceStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("Device disconnected!");
          connectedDevice = null;
          leftCm = null;
          centerCm = null;
          rightCm = null;
          notifyListeners();
        }
      });

      print("Connection successful. Discovering services...");
      List<BluetoothService> services = await device.discoverServices();

      for (var service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          for (var char in service.characteristics) {
            final charUuid = char.uuid.toString();
            if (charUuid == DISTANCE_CHAR_UUID) {
              distanceChar = char;
            } else if (charUuid == SETTINGS_CHAR_UUID) {
              settingsChar = char;
            }
          }
        }
      }

      if (distanceChar != null) _startDistanceUpdates();
      notifyListeners();
    } catch (e) {
      print("❌ CONNECTION ERROR: $e");
      connectedDevice = null;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _deviceStateSub?.cancel();
    await connectedDevice?.disconnect();
    connectedDevice = null;
    distanceChar = null;
    settingsChar = null;
    leftCm = null;
    centerCm = null;
    rightCm = null;
    notifyListeners();
  }

  Future<void> hardcodeConnect() async {
    if (!(await _checkAndRequestPermissions())) return;
    final device = BluetoothDevice.fromId(HARDCODED_DEVICE_ID);
    await connect(device);
  }

  Future<void> scanAndAutoConnect() async {
    startScan();
    await Future.delayed(const Duration(seconds: 5));
    if (scanResults.isNotEmpty && !isConnected) {
      await connect(scanResults.first.device);
    }
  }

  // --- Data Read/Write Methods ---
  Future<void> writeSettings(int cautionCm, int dangerCm) async {
    if (settingsChar != null) {
      await settingsChar!.write([cautionCm, dangerCm]);
    }
  }

  void _startDistanceUpdates() {
    if (distanceChar == null) return;

    distanceChar!.setNotifyValue(true).then((success) {
      if (!success) print("⚠️ Failed to enable notifications");
    });

    distanceChar!.value.listen((data) {
      if (data.length >= 3) {
        leftCm = data[0].toDouble();
        centerCm = data[1].toDouble();
        rightCm = data[2].toDouble();
        notifyListeners();
      } else {
        print("⚠️ Data packet too short: ${data.length}");
      }
    });
  }

  Future<void> sendData(bool buzzer, int dangerCm) async {
    dangerCm = dangerCm & 0x7F; // ensure 7-bit
    int firstByte = (buzzer ? 0x80 : 0x00) | dangerCm;
    List<int> data = [firstByte];

    if (settingsChar != null) {
      await settingsChar!.write(data);
      print("📢 Sent data: $data");
    } else {
      print("⚠️ No settings characteristic found");
    }
  }

  void disposeService() {
    _deviceStateSub?.cancel();
    connectedDevice?.disconnect();
  }
}
