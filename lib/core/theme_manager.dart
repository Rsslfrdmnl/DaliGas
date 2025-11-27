// lib/core/theme_manager.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/web/main_web.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('darkMode') ?? false;

    // If admin is logged in → respect Firestore setting
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await firestore
            .collection('admins')
            .doc(user.uid)
            .get();
        if (doc.exists && doc.data()?['darkMode'] != null) {
          final fromFirestore = doc.data()!['darkMode'] as bool;
          _themeMode = fromFirestore ? ThemeMode.dark : ThemeMode.light;
          await prefs.setBool('darkMode', fromFirestore);
        } else {
          _themeMode = saved ? ThemeMode.dark : ThemeMode.light;
        }
      } catch (e) {
        _themeMode = saved ? ThemeMode.dark : ThemeMode.light;
      }
    } else {
      _themeMode = saved ? ThemeMode.dark : ThemeMode.light;
    }

    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', isDark);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await firestore
          .collection('admins')
          .doc(user.uid)
          .set({'darkMode': isDark}, SetOptions(merge: true));
    }

    notifyListeners();
  }
}