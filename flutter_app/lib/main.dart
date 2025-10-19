import 'package:flutter/material.dart';
import 'screens/planner_screen.dart';
import 'models/user_tier.dart';

void main() {
  runApp(const Flow7App());
}

class Flow7App extends StatelessWidget {
  const Flow7App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flow7 - Weekly Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
      ),
      home: const PlannerScreen(
        userTier: UserTier.free, // Change this to test different tiers
        apiBaseUrl: 'http://localhost:8000',
      ),
    );
  }
}
