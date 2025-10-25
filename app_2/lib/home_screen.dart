import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool _buzzerActive = false;

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
            title: const Text('Magic White Cane'),
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
          Text(
            b.isConnected ? "$deviceName connected" : "Not connected",
            style: const TextStyle(fontSize: 16),
          ),
          // Scrollable button row to prevent overflow
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  children: [
                    if (!b.isConnected)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ElevatedButton(
                          onPressed: () => b.hardcodeConnect(),
                          child: const Text("Hardcode Connect"),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: b.isConnected
                          ? () => b.disconnect()
                          : () => b.scanAndAutoConnect(),
                      child: Text(b.isConnected ? "Disconnect" : "Auto Connect"),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: b.scanning ? b.stopScan : () => b.startScan(),
                      child: Text(b.scanning ? "Stop Scan" : "Scan"),
                    ),
                    const SizedBox(width: 6),
                    if (b.isConnected)
                      ElevatedButton(
                        onPressed: () async {
                          setState(() => _buzzerActive = !_buzzerActive);
                          await b.sendData(_buzzerActive, dangerCm);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _buzzerActive ? Colors.red : Colors.blue,
                        ),
                        child: Text(
                          _buzzerActive ? "Stop Beep 🔇" : "Find My Cane 🔔",
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
          final deviceName = r.device.platformName ?? r.device.remoteId.str;
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
          _singleReadout("Center", b.centerCm),
          const SizedBox(height: 24),
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
    final displayValue = (cm == null || cm > 250.0)
        ? 'N/A'
        : cm.toStringAsFixed(1);

    Color circleColor;
    if (cm == null || cm > 250.0) {
      circleColor = Colors.grey;
    } else if (cm <= dangerCm) {
      circleColor = Colors.red.shade700;
    } else if (cm <= cautionCm) {
      circleColor = Colors.orange.shade700;
    } else {
      circleColor = Colors.green.shade700;
    }

    const double circleSize = 100.0;

    return Container(
      width: circleSize,
      height: circleSize,
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            displayValue == 'N/A' ? 'N/A' : '$displayValue cm',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(builder: (context, setDialogState) {
          // Track validity
          bool dangerValid = true;
          bool cautionValid = true;

          int? dangerVal = int.tryParse(dangerCtl.text);
          int? cautionVal = int.tryParse(cautionCtl.text);

          if (dangerVal == null || dangerVal < 1 || dangerVal > 127) {
            dangerValid = false;
          }

          if (cautionVal == null || dangerVal == null || cautionVal <= dangerVal) {
            cautionValid = false;
          }

          bool formValid = dangerValid && cautionValid;

          return AlertDialog(
            title: const Text("Settings"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dangerCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: "Danger cm (1–127)",
                    errorText: dangerValid ? null : "Must be 1–127",
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: dangerValid ? Colors.grey : Colors.red,
                      ),
                    ),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cautionCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: "Caution cm (> Danger)",
                    errorText: cautionValid ? null : "Must be > Danger",
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: cautionValid ? Colors.grey : Colors.red,
                      ),
                    ),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: formValid
                    ? () {
                        setState(() {
                          cautionCm = cautionVal!;
                          dangerCm = dangerVal!;
                        });
                        b.writeSettings(cautionCm, dangerCm);
                        b.sendData(_buzzerActive, dangerCm);
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text("Save"),
              ),
            ],
          );
        });
      },
    );
  }
}
