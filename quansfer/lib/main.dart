import 'package:flutter/material.dart';
import 'pages/home_page.dart';

void main() {
  runApp(const QuansferApp());
}

class QuansferApp extends StatelessWidget {
  const QuansferApp({super.key});

  @override
  Widget build(BuildContext context) {
    const baseUrl = 'http://192.168.100.149:8000'; // IP DE MI PC
    return MaterialApp(
      title: 'quansfer',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomePage(baseUrl: baseUrl),
    );
  }
}
