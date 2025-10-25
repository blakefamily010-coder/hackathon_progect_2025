import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

// No need for typedefs, the classes are imported directly.

class BleService extends ChangeNotifier {
  // Bluetooth Classic Serial fields
  BluetoothConnection? connection;
  BluetoothDevice? connectedDevice;
  
  bool scanning = false;
  List<BluetoothDevice> pairedDevices = [];
  
  // Data variables
  double? leftCm;
  double? centerCm;
  double? rightCm;

  // Stream subscription for incoming data
  StreamSubscription<Uint8List>? _dataSubscription;

  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  
  BleService._internal() {
    // Start listening for Bluetooth state changes on initialization
    FlutterBluetoothSerial.instance.onStateChanged().listen((BluetoothState state) {
      if (state == BluetoothState.STATE_OFF) {
        // Disconnect if Bluetooth is turned off
        disconnect();
      }
      notifyListeners();
    });
  }

  bool get isConnected => connection?.isConnected ?? false;

  Future<bool> get isBluetoothEnabled async => await FlutterBluetoothSerial.instance.isEnabled ?? false;

  /// Helper function: Checks and requests permissions
  Future<bool> _checkAndRequestPermissions() async {
    // Bluetooth Classic and location permissions for Android
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.location, // Still often required for BT Classic discovery/pairing
    ].request();

    bool allGranted = statuses[Permission.bluetooth]?.isGranted == true &&
                      statuses[Permission.location]?.isGranted == true;

    // You might want to show a dialog here if permissions are denied
    return allGranted;
  }

  /// Scan for paired devices and auto-connect to the ESP32
  Future<void> scanAndAutoConnect() async {
    if (!await _checkAndRequestPermissions()) return;
    
    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
    if (!isEnabled) {
      // Prompt user to enable Bluetooth
      await FlutterBluetoothSerial.instance.requestEnable();
      return;
    }
    
    // Get list of paired devices
    pairedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
    notifyListeners();

    // The ESP32 name is "ESP32test1" from your hardware.ino file
    final esp32 = pairedDevices.firstWhereOrNull(
      (device) => device.name == "ESP32test1"
    );

    if (esp32 != null && !isConnected) {
      await connect(esp32);
    }
  }

  // NOTE: This version of BT Classic doesn't have a separate 'startScan' 
  // method to find UNPAIRED devices. It primarily works with bonded devices.
  void startScan() {
    // Scanning for new devices in BT Classic is a different process (discovery)
    // We will just call scanAndAutoConnect to check for bonded devices
    scanAndAutoConnect();
  }

  void stopScan() {
    // No need to stop a scan for bonded devices
  }


  /// Connect to the given device
  Future<void> connect(BluetoothDevice device) async {
    try {
      connection = await BluetoothConnection.toAddress(device.address);
      connectedDevice = device;
      
      _startDataUpdates();
      notifyListeners();
      
      print('Connected to ${device.name} at ${device.address}');

    } catch (e) {
      print('Connection failed: $e');
      connection = null;
      connectedDevice = null;
      notifyListeners();
    }
  }

  /// Disconnect from the current device
  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
    await connection?.finish();
    connection = null;
    connectedDevice = null;
    leftCm = null;
    centerCm = null;
    rightCm = null;
    notifyListeners();
    print('Disconnected');
  }
  
  /// Send a string over the Bluetooth serial connection
  Future<void> writeData(String data) async {
    if (connection?.isConnected == true) {
      // Encode the string to bytes (ASCII is common for serial)
      connection!.output.add(ascii.encode(data));
      await connection!.output.allSent;
      print('Sent: $data');
    }
  }
  
  /// Send updated caution/danger settings to the ESP32
  Future<void> writeSettings(int cautionCm, int dangerCm) async {
    // Simple command format for the ESP32 to receive and parse
    final settingsString = "SETTINGS,C:$cautionCm,D:$dangerCm\n";
    await writeData(settingsString);
  }


  /// NEW method for listening to the serial data stream and parsing JSON
  void _startDataUpdates() {
    if (connection != null && connection!.isConnected) {
      _dataSubscription?.cancel();
      
      // We need a buffer to re-assemble packets that arrive in chunks
      String buffer = "";
      
      _dataSubscription = connection!.input!.listen((Uint8List data) {
        
        // Convert the incoming bytes to a string
        buffer += ascii.decode(data);
        
        // Look for a newline character, which should terminate your data packet
        int newlineIndex = buffer.indexOf('\n');
        
        // While there is a complete packet in the buffer
        while (newlineIndex != -1) {
          String message = buffer.substring(0, newlineIndex).trim();
          
          // Remove the processed message from the buffer
          buffer = buffer.substring(newlineIndex + 1);
          
          if (message.startsWith('{') && message.endsWith('}')) {
            try {
              // WORKAROUND for the invalid JSON from your hardware.ino: "{\\"distace0\\":\\"%f\\",}"
              // which produces: {"distace0":"123.456",} <-- Note the trailing comma
              if (message.endsWith(',}')) {
                message = '${message.substring(0, message.length - 2)}}';
              }

              final Map<String, dynamic> jsonMap = jsonDecode(message);
              // Your hardware.ino uses 'distace0'. We map this to centerCm for your app's logic.
              final String? distanceString = jsonMap['distace0'] ?? jsonMap['centerCm']; 

              if (distanceString != null) {
                // Ensure it's parsed as a double
                final double? distance = double.tryParse(distanceString);
                if (distance != null) {
                  centerCm = distance;
                  // For now, left and right are null since your hardware only sends one
                  leftCm = null;
                  rightCm = null; 
                  notifyListeners();
                }
              }
            } catch (e) {
              print('Error decoding or parsing JSON: $e, message: $message');
            }
          }
          
          // Check for the next complete packet
          newlineIndex = buffer.indexOf('\n');
        }

      }, 
      onDone: () {
        // Runs when the remote device disconnects gracefully
        disconnect();
      }, 
      onError: (error) {
        print('Bluetooth data stream error: $error');
        disconnect();
      });
    }
  }
}

// Helper extension to find a device in a list
extension on List<BluetoothDevice> {
  BluetoothDevice? firstWhereOrNull(bool Function(BluetoothDevice) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}