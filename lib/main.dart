import 'package:flutter/material.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const Flow7App());
}

class Flow7App extends StatelessWidget {
  const Flow7App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flow7',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
