import 'package:flutter/material.dart';

void main() {
  runApp(const YenefsAbatApp());
}

class YenefsAbatApp extends StatelessWidget {
  const YenefsAbatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yenefs Abat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B0F1A), // dark red church color
        ),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            '✝️ Yenefs Abat',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
