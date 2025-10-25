import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart'; // 💡 NEW IMPORT

class BleService extends ChangeNotifier {
  // ... (Existing instance variables)
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? distanceChar;
  BluetoothCharacteristic? settingsChar;
  bool scanning = false;
  List<ScanResult> scanResults = [];
  double? leftCm;
  double? centerCm;
  double? rightCm;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSub;

  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  bool get isConnected => connectedDevice != null;

  // 💡 NEW HELPER FUNCTION: Checks and requests permissions
  Future<bool> _checkAndRequestPermissions() async {
    // Request new Android 12+ Bluetooth permissions and Location (required by FlutterBluePlus)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Check if all essential permissions were granted
    bool allGranted = statuses[Permission.bluetoothScan]?.isGranted == true &&
                      statuses[Permission.bluetoothConnect]?.isGranted == true &&
                      statuses[Permission.location]?.isGranted == true;
    
    if (!allGranted) {
      // You might want to display a dialog explaining why permissions are needed
      print("Bluetooth or Location permissions denied. Cannot start scan.");
    }
    
    return allGranted;
  }

  /// Start scanning for BLE devices
  void startScan() async { // 💡 MUST BE async now
    // 💡 CALL THE PERMISSION CHECK BEFORE SCANNING
    if (!(await _checkAndRequestPermissions())) {
       return; 
    }
    
    if (scanning) return;
    scanning = true;
    scanResults.clear();
    notifyListeners();

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      for (var result in results) {
        if (!scanResults.any((r) => r.device.remoteId == result.device.remoteId)) {
          scanResults.add(result);
          notifyListeners();
        }
      }
    });

    // Start scanning (static method)
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5)).whenComplete(() {
      scanning = false;
      notifyListeners();
    });
  }

  /// Stop scanning
  void stopScan() {
    FlutterBluePlus.stopScan();
    scanning = false;
    notifyListeners();
  }

  // ... (rest of connect, disconnect, etc. methods remain the same)
  Future<void> connect(BluetoothDevice device) async {
    // ...
  }

  Future<void> disconnect() async {
    // ...
  }
  
  Future<void> scanAndAutoConnect() async {
    startScan();
    await Future.delayed(const Duration(seconds: 5));
    if (scanResults.isNotEmpty && !isConnected) {
      await connect(scanResults.first.device);
    }
  }

  Future<void> writeSettings(int cautionCm, int dangerCm) async {
    if (settingsChar != null) {
      final value = [cautionCm, dangerCm];
      await settingsChar!.write(value);
    }
  }

  void _startDistanceUpdates() {
    if (distanceChar != null) {
      distanceChar!.setNotifyValue(true);
      distanceChar!.value.listen((data) {
        if (data.length >= 6) {
          leftCm = data[0].toDouble();
          centerCm = data[2].toDouble();
          rightCm = data[4].toDouble();
          notifyListeners();
        }
      });
    }
  }

  void disposeService() {
    _deviceStateSub?.cancel();
    connectedDevice?.disconnect();
  }
}