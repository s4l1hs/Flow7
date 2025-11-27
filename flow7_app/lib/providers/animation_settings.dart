import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnimationSettings extends ChangeNotifier {
  bool _enabled = true;
  AnimationSettings([this._enabled = true]);

  bool get enabled => _enabled;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('animations_enabled') ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('animations_enabled', value);
    } catch (_) {}
    notifyListeners();
  }
}
