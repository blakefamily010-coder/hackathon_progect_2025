import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService extends ChangeNotifier {
  // 💡 NEW CONSTANT: Replace this placeholder with your ESP32's actual MAC address/Remote ID
  static const String HARDCODED_DEVICE_ID = "A0:A3:B3:AA:FD:66"; 

  // --- Existing Instance Variables ---
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
      print("Bluetooth or Location permissions denied. Cannot start scan or connect.");
    }
    
    return allGranted;
  }

  /// Start scanning for BLE devices
  void startScan() async {
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

  /// Connect to a given device
  Future<void> connect(BluetoothDevice device) async {
    if (isConnected) await disconnect();

    try {
      // Connect to the device
      await device.connect(license:License.free);

      // Set up connection state listener
      _deviceStateSub = device.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("Device disconnected!");
          connectedDevice = null;
          notifyListeners();
        }
      });

      connectedDevice = device;
      
      // Discover services and find characteristics
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        // Replace with your actual Service UUIDs if you use filtering
        // For simplicity, we assume we look at all services here.
        for (var char in service.characteristics) {
          // Replace these with your actual Characteristic UUIDs
          if (char.uuid.toString().toUpperCase() == "FFE1") {
            distanceChar = char;
          } else if (char.uuid.toString().toUpperCase() == "FFE1") {
            settingsChar = char;
          }
        }
      }

      if (distanceChar != null) {
        _startDistanceUpdates();
      }

      notifyListeners();
    } catch (e) {
      print("Connection failed: $e");
      connectedDevice = null;
      notifyListeners();
    }
  }

  /// Disconnect from the current device
  Future<void> disconnect() async {
    _deviceStateSub?.cancel();
    await connectedDevice?.disconnect();
    connectedDevice = null;
    distanceChar = null;
    settingsChar = null;
    notifyListeners();
  }
  
  // 💡 NEW METHOD: Direct hardcoded connection
  Future<void> hardcodeConnect() async {
    // 1. Check for necessary permissions first
    if (!(await _checkAndRequestPermissions())) {
        return; 
    }

    // 2. Create the device object from the hardcoded ID
    final device = BluetoothDevice.fromId(HARDCODED_DEVICE_ID);

    // 3. Connect using the existing connect logic
    await connect(device);
  }

  /// Automatically scan and connect to the first found device
  Future<void> scanAndAutoConnect() async {
    startScan();
    await Future.delayed(const Duration(seconds: 5));
    if (scanResults.isNotEmpty && !isConnected) {
      await connect(scanResults.first.device);
    }
  }

  Future<void> writeSettings(int cautionCm, int dangerCm) async {
    if (settingsChar != null) {
      // Note: This assumes your ESP32 expects two single-byte integers
      final value = [cautionCm, dangerCm]; 
      await settingsChar!.write(value);
    }
  }

  void _startDistanceUpdates() {
    if (distanceChar != null) {
      distanceChar!.setNotifyValue(true);
      distanceChar!.value.listen((data) {
        if (data.length >= 6) {
          // Assuming 1 byte per value (data[0], data[2], data[4] are odd indices from the original sketch)
          // If the data is received as a packed byte array (e.g., 3 values, 2 bytes each, total 6 bytes):
          // leftCm = (data[0] * 256 + data[1]).toDouble(); 
          // centerCm = (data[2] * 256 + data[3]).toDouble();
          // rightCm = (data[4] * 256 + data[5]).toDouble();

          // Using the simpler 1-byte per value logic from the original sketch for now:
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