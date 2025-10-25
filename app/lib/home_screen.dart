// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_service.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
// ADDED for device type in the list tile
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _hapticTimer;

  int cautionCm = 120;
  int dangerCm = 50;

  @override
  void dispose() {
    _hapticTimer?.cancel();
    super.dispose();
  }

  void _maybeTriggerHaptics(BleService b) async {
    _hapticTimer?.cancel();

    final left = b.leftCm;
    final center = b.centerCm;
    final right = b.rightCm;

    // The ESP32 only sends a single sensor's data (centerCm), so we only check 'center'
    // We can comment out the full check if it's only a single sensor project
    // if (left == null || center == null || right == null) return;
    if (center == null) return; // Only check the sensor that is actually sending data
    
    // For single sensor, we only check the center distance
    bool danger = (center <= dangerCm);
    bool caution = (center <= cautionCm);

    if (danger) {
      _hapticTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
        // Fix: Using ?? false to safely handle nullable result from Future<bool?>
        if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 250);
      });
    } else if (caution) {
      _hapticTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        // Fix: Using ?? false to safely handle nullable result from Future<bool?>
        if (await Vibration.hasCustomVibrationsSupport() ?? false) {
          Vibration.vibrate(pattern: <int>[0, 100, 150, 100]);
        } else {
          Vibration.vibrate(duration: 80);
        }
      });
    } else {
      _hapticTimer?.cancel();
      _hapticTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, b, _) {
        _maybeTriggerHaptics(b);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Smart Cane'),
            actions: [
              IconButton(
                onPressed: () => _showSettingsDialog(context, b),
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
          body: Column(
            children: [
              const SizedBox(height: 8),
              _connectionRow(b),
              const Divider(),
              // ⚠️ NEW: Changed to _pairedDeviceList for BT Classic
              _pairedDeviceList(b),
              const Divider(),
              Expanded(child: _readouts(b)),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _connectionRow(BleService b) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            b.isConnected
                // ⚠️ FIX: Use the connectedDevice property from BleService
                ? "${b.connectedDevice?.name ?? b.connectedDevice?.address ?? 'Device'} connected"
                : "Not connected",
            style: const TextStyle(fontSize: 16),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: b.isConnected
                ? () => b.disconnect()
                // ⚠️ FIX: Call auto-connect which also performs the check for paired devices
                : () => b.scanAndAutoConnect(), 
            child: Text(b.isConnected ? "Disconnect" : "Auto Connect"),
          ),
          const SizedBox(width: 8),
          // ⚠️ FIX: Removed the 'Scan' button as the auto-connect function 
          // now handles listing paired devices, which is the standard BT Classic approach.
          // You could replace this with a button to simply load bonded devices if needed.
          ElevatedButton(
            // Since BT Classic primarily uses BONDED devices, a simple 'Refresh' of the list is often enough.
            onPressed: () => b.scanAndAutoConnect(), 
            child: const Text("Load Paired"),
          ),
        ],
      ),
    );
  }

  // ⚠️ NEW: Widget to display Paired Devices for Bluetooth Classic
  Widget _pairedDeviceList(BleService b) {
    // If connected, show nothing in the list.
    if (b.isConnected) {
      return const SizedBox(height: 0);
    }
    
    // Show a message if no devices were loaded or found.
    if (b.pairedDevices.isEmpty) {
       return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('No paired devices found. Ensure the ESP32 is paired via OS settings.'),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        itemCount: b.pairedDevices.length,
        itemBuilder: (context, i) {
          // ⚠️ FIX: Use the BluetoothDevice type directly from the imported library
          final BluetoothDevice device = b.pairedDevices[i]; 
          
          final deviceName = device.name ?? 'Unknown Device';

          return ListTile(
            title: Text(deviceName),
            subtitle: Text(device.address),
            trailing: ElevatedButton(
              // ⚠️ FIX: Pass the BluetoothDevice object to connect
              onPressed: () => b.connect(device), 
              child: const Text('Connect'),
            ),
          );
        },
      ),
    );
  }

  Widget _readouts(BleService b) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _singleReadout("Center", b.centerCm),
          const SizedBox(height: 12),
          // The hardware only supports one sensor, so left and right will be null/0.
          // Keep the UI layout for future expansion.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _singleReadout("Left", b.leftCm)),
              const SizedBox(width: 12),
              Expanded(child: _singleReadout("Right", b.rightCm)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _singleReadout(String label, double? cm) {
    final display = (cm == null || cm >= 9999) ? "--" : "${cm.toStringAsFixed(0)} cm";
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(display, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettingsDialog(BuildContext context, BleService b) async {
    final cautionCtl = TextEditingController(text: cautionCm.toString());
    final dangerCtl = TextEditingController(text: dangerCm.toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cautionCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Caution cm"),
            ),
            TextField(
              controller: dangerCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Danger cm"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              int c = int.tryParse(cautionCtl.text) ?? cautionCm;
              int d = int.tryParse(dangerCtl.text) ?? dangerCm;
              
              setState(() {
                cautionCm = c;
                dangerCm = d;
              });

              // The call is correct for the updated BleService.writeSettings signature
              b.writeSettings(c, d); 
              Navigator.pop(context);
            },
            child: const Text("Save"),
          )
        ],
      ),
    );
  }
}