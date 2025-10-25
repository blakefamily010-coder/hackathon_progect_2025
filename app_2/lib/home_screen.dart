import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, b, _) {
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
    final deviceName = b.isConnected 
        ? b.connectedDevice!.platformName ?? b.connectedDevice!.remoteId.str
        : "Not connected";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Connection Status Text
          Text(
            b.isConnected
                ? "$deviceName connected"
                : "Not connected",
            style: const TextStyle(fontSize: 16),
          ),
          
          // Buttons Row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hardcode Connect Button
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
          final deviceName =
              r.device.platformName ?? r.device.remoteId.str;
          return ListTile(
            title: Text(deviceName), 
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
          // The Center Readout (now a circle)
          _singleReadout("Center", b.centerCm), 
          
          // Removed the placeholder SizedBox, but kept the spacing between elements
          const SizedBox(height: 24, ), 
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _singleReadout("Left", b.leftCm)),
              const SizedBox(width: 12), // Spacing between Left/Right circles
              Expanded(child: _singleReadout("Right", b.rightCm)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _singleReadout(String label, double? cm) {
    // 1. Calculate the value to display: 
    //    - If null OR > 250, display 'N/A'.
    //    - Otherwise, display the value formatted to one decimal place.
    //    - NOTE: The original code checked for '9999' which I've replaced with 250
    //            and also added the null check for 'N/A'.
    final displayValue = (cm == null || cm > 250.0)
        ? 'N/A'
        : cm.toStringAsFixed(1); // Use 1 decimal place as per previous request

    // 2. Determine the color based on the sensor value (optional, but good visual feedback)
    Color circleColor;
    if (cm == null || cm > 250.0) {
      circleColor = Colors.grey; // Not connected/out of range
    } else if (cm <= dangerCm) {
      circleColor = Colors.red.shade700; // Danger
    } else if (cm <= cautionCm) {
      circleColor = Colors.orange.shade700; // Caution
    } else {
      circleColor = Colors.green.shade700; // Clear
    }
    
    // Define a size for the circular container
    const double circleSize = 100.0; 

    return Container(
      width: circleSize, // Must be equal to height for a circle
      height: circleSize,
      
      // 🎨 Apply the Circle Decoration
      decoration: BoxDecoration(
        color: circleColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: circleColor.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      
      // Content is centered inside the circle
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The Label (e.g., "Center")
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 4),
          
          // The Value (e.g., "150.0 cm" or "N/A")
          Text(
            // Display the N/A or the formatted value with " cm" added
            displayValue == 'N/A' ? 'N/A' : '$displayValue cm',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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