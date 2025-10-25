// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_service.dart';
import 'home_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleService()),
      ],
      child: const SmartCaneApp(),
    ),
  );
}

class SmartCaneApp extends StatelessWidget {
  const SmartCaneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Cane',
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}
