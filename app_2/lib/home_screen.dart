// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_service.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';

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

    if (left == null || center == null || right == null) return;

    bool danger = (center <= dangerCm) || (left <= dangerCm) || (right <= dangerCm);
    bool caution = (center <= cautionCm) || (left <= cautionCm) || (right <= cautionCm);

    if (danger) {
      _hapticTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
        // Safe check for nullable result from Future<bool?>
        if (await Vibration.hasVibrator() == true) Vibration.vibrate(duration: 250);
      });
    } else if (caution) {
      _hapticTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        // Safe check for nullable result from Future<bool?>
        if (await Vibration.hasCustomVibrationsSupport() == true) {
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
              _scanList(b),
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
    // FIX: Simplified the expression. Since b.isConnected is true, b.connectedDevice is not null. 
    final deviceName = b.isConnected 
        ? b.connectedDevice!.platformName ?? b.connectedDevice!.remoteId.str
        : "Not connected";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // Adjust alignment for more buttons
        children: [
          // Connection Status Text
          Text(
            b.isConnected
                ? "$deviceName connected"
                : "Not connected",
            style: const TextStyle(fontSize: 16),
          ),
          
          // Use a Row for the buttons to keep them together
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 💡 NEW BUTTON: Hardcode Connect
              if (!b.isConnected) 
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ElevatedButton(
                    onPressed: () => b.hardcodeConnect(),
                    child: const Text("Hardcode Connect"),
                  ),
                ),

              // Auto Connect/Disconnect Button
              ElevatedButton(
                onPressed: b.isConnected
                    ? () => b.disconnect()
                    : () => b.scanAndAutoConnect(),
                child: Text(b.isConnected ? "Disconnect" : "Auto Connect"),
              ),

              const SizedBox(width: 8),
              
              // Scan Button
              ElevatedButton(
                onPressed: b.scanning ? b.stopScan : () => b.startScan(),
                child: Text(b.scanning ? "Stop Scan" : "Scan"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scanList(BleService b) {
    if (b.scanning) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('Scanning...'),
      );
    }
    return SizedBox(
      height: 120,
      child: ListView.builder(
        itemCount: b.scanResults.length,
        itemBuilder: (context, i) {
          final r = b.scanResults[i];
          // Code is already correct, as r.device.remoteId.str is non-nullable String.
          final deviceName =
              r.device.platformName ?? r.device.remoteId.str;
          return ListTile(
            title: Text(deviceName), 
            // Subtitle updated to show ID and RSSI for clarity
            subtitle: Text("ID: ${r.device.remoteId.str} | RSSI: ${r.rssi}"),
            trailing: ElevatedButton(
              onPressed: () => b.connect(r.device),
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