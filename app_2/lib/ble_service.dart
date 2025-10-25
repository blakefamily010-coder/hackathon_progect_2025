// ble_service.dart

import 'dart:async';
import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService extends ChangeNotifier {
  // ⚠️ CRITICAL: Must match your ESP32's MAC address exactly
  static const String HARDCODED_DEVICE_ID = "A0:A3:B3:AA:FD:66"; 

  // ⚠️ CRITICAL: UUIDs MUST match the ESP32 sketch EXACTLY
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

  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  bool get isConnected => connectedDevice != null;

  // --- Permission Handling ---
  Future<bool> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses[Permission.bluetoothScan]?.isGranted == true &&
                      statuses[Permission.bluetoothConnect]?.isGranted == true &&
                      statuses[Permission.location]?.isGranted == true;
    
    if (!allGranted) {
      print("Bluetooth or Location permissions denied. Cannot proceed.");
    }
    
    return allGranted;
  }

  // --- Scanning Methods ---
  void startScan() async {
    if (!(await _checkAndRequestPermissions())) {
        return; 
    }
    
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

  /// Connect to a given device
  Future<void> connect(BluetoothDevice device) async {
    if (isConnected) await disconnect();

    try {
      print("Attempting to connect to: ${device.remoteId.str}");
      
      await device.connect(timeout: const Duration(seconds: 10),license: License.free); 

      _deviceStateSub = device.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          print("Device disconnected!");
          connectedDevice = null;
          // Clear readouts on disconnect
          leftCm = null;
          centerCm = null;
          rightCm = null;
          notifyListeners();
        }
      });

      connectedDevice = device;
      print("Connection successful. Discovering services...");

      // Discover services and find characteristics
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
           print("Found Smart Cane Service: ${service.uuid.str}");
           
           for (var char in service.characteristics) {
             final charUuid = char.uuid.toString();

             if (charUuid == DISTANCE_CHAR_UUID) {
               distanceChar = char;
               print("Found Distance Characteristic.");
             } else if (charUuid == SETTINGS_CHAR_UUID) {
               settingsChar = char;
               print("Found Settings Characteristic.");
             }
           }
        }
      }

      if (distanceChar != null) {
        _startDistanceUpdates();
      } else {
         print("ERROR: Distance characteristic not found or connection failed.");
      }

      notifyListeners();
    } catch (e) {
      print("FATAL CONNECTION/SERVICE DISCOVERY ERROR: $e");
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
    leftCm = null;
    centerCm = null;
    rightCm = null;
    notifyListeners();
  }
  
  /// Direct hardcoded connection
  Future<void> hardcodeConnect() async {
    if (!(await _checkAndRequestPermissions())) {
        return; 
    }
    final device = BluetoothDevice.fromId(HARDCODED_DEVICE_ID);
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

  // --- Data Read/Write Methods ---

  Future<void> writeSettings(int cautionCm, int dangerCm) async {
    if (settingsChar != null) {
      final value = [cautionCm, dangerCm]; 
      await settingsChar!.write(value);
    }
  }

  void _startDistanceUpdates() {
    if (distanceChar != null) {
      // 1. CRITICAL STEP: Ensure notifications are enabled
      distanceChar!.setNotifyValue(true).then((success) {
        if (success) {
            print("✅ Distance characteristic notifications ENABLED.");
        } else {
            print("❌ ERROR: Distance characteristic notifications FAILED to enable.");
            return;
        }
      });
      
      distanceChar!.value.listen((data) {
        // 2. 🎯 DIAGNOSTIC: Prints the raw byte array received from the ESP32
        // print('➡️ RECEIVED RAW BYTES: $data, Length: ${data.length}');
        
        if (data.length >= 3) {
          // Parse the 6-byte packet: [L, P, C, P, R, P]
          // The parsing logic is correct for the ESP32 test sketch format.
          leftCm = data[0].toDouble();
          centerCm = data[1].toDouble(); 
          rightCm = data[2].toDouble();

          // print('Parsed Values: Center=${centerCm?.toStringAsFixed(0)}');

          notifyListeners();
        } else {
           print('⚠️ Warning: Received data packet is too short (${data.length} bytes).');
        }
      });
    }
  }

Future<void> buzzerOn() async {
  if (settingsChar != null) {
    await settingsChar!.write([0xF0]); // Command: Start buzzer
    print("📢 Buzzer ON command sent");
  } else {
    print("⚠️ No settings characteristic found");
  }
}

Future<void> sendData(bool buzzer, int dangerCm) async {
  dangerCm = dangerCm & 0x7F; // ensure 7-bit
  int firstByte = (buzzer ? 0x80 : 0x00) | dangerCm;
  List<int> data = [firstByte];
  print("Bool: $buzzer");
  print("dangerCM: $dangerCm");
  print("Sending byte: $firstByte"); // shows decimal value
  print("Binary: ${firstByte.toRadixString(2).padLeft(8, '0')}");

  if (settingsChar != null) {
    await settingsChar!.write(data);
    print("Settings sent");
  } else {
    print("⚠️ No settings characteristic found");
  }
}





  void disposeService() {
    _deviceStateSub?.cancel();
    connectedDevice?.disconnect();
  }
}