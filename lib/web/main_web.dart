// lib/web/main_web.dart
import 'dart:html' as html;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:daligas/firebase_options.dart';

import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'package:daligas/web/screens/super_admin/super_dashboard_screen.dart';
import 'package:daligas/web/screens/sub_admin/admin_dashboard_screen.dart';

// Global Firestore instance
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'daligas',
);

// ──────────────────────────────
// Theme Manager (Singleton)
// ──────────────────────────────
class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> loadTheme() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await firestore.collection('admins').doc(user.uid).get();
        if (doc.exists && doc.data()?['darkMode'] is bool) {
          final bool dark = doc.data()!['darkMode'];
          _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
        }
      } catch (e) {
        // fallback to light
      }
    }
    notifyListeners();
  }

  Future<void> setDarkMode(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await firestore.collection('admins').doc(user.uid).set({
        'darkMode': isDark,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}

// ──────────────────────────────
// Beautiful Themes
// ──────────────────────────────
final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  fontFamily: 'Roboto',
  primaryColor: const Color(0xFF0D2236),
  scaffoldBackgroundColor: Colors.grey[50],
  cardColor: null,
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0D2236),
    foregroundColor: null,
    elevation: 0,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF0D2236),
      foregroundColor: null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF0D2236), width: 2),
    ),
  ),
);

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'Roboto',
  primaryColor: const Color(0xFF0D2236),

  // Core dark mode colors that automatically apply to all cards/containers
  scaffoldBackgroundColor: const Color(0xFF0A0E17),    // Main page background
  cardColor: const Color(0xFF16213E),                  // All cards, containers, dialogs
  canvasColor: const Color(0xFF16213E),                // Secondary backgrounds
  dialogBackgroundColor: const Color(0xFF16213E),     // Dialogs and bottom sheets
  
  dividerColor: const Color(0xFF2D3748),               // Dividers and borders
  hoverColor: const Color(0xFF2A4066).withOpacity(0.3),

  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Color(0xFFE4E6EB)),   // Primary text
    bodyMedium: TextStyle(color: Color(0xFFB0B3B8)), // Secondary text
    titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    labelLarge: TextStyle(color: Color(0xFFB0B3B8)),
  ),

  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0D2236),
    foregroundColor: Colors.white,
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Color(0xFF0D2236),
      foregroundColor: Colors.white,
    ),
  ),

  inputDecorationTheme: const InputDecorationTheme(
    filled: true,
    fillColor: Color(0xFF1A2338),                      // Text field backgrounds
    hintStyle: TextStyle(color: Color(0xFF64748B)),
    border: OutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFF2D3748)),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFF2D3748)),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFF0D2236), width: 2),
    ),
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load Google Maps JS only once
  if (kIsWeb) {
    final existing = html.document.querySelector('script[src*="maps.googleapis.com"]');
    if (existing == null) {
      final script = html.ScriptElement()
        ..src = "https://maps.googleapis.com/maps/api/js?key=AIzaSyAVDDHYb29rt4io-HI0Uq6vfv_GAnlDLlw&libraries=places&loading=async"
        ..async = true
        ..defer = true;
      html.document.head!.append(script);
    }
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  // Load theme BEFORE running app
  await ThemeManager().loadTheme();

  runApp(const MyWebApp());
}

class MyWebApp extends StatelessWidget {
  const MyWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeManager(),
      builder: (context, child) {
        return MaterialApp(
          title: 'DALIGAS Admin',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: ThemeManager().themeMode,
          home: const AuthGate(),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────
// AuthGate & Role Checker (unchanged, just cleaner)
// ────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.data == null) {
          return AdminWelcomeScreen();
        }

        return _RoleChecker(user: snapshot.data!);
      },
    );
  }
}

class _RoleChecker extends StatefulWidget {
  final User user;
  const _RoleChecker({required this.user});

  @override
  State<_RoleChecker> createState() => _RoleCheckerState();
}

class _RoleCheckerState extends State<_RoleChecker> {
  @override
  void initState() {
    super.initState();
    _checkRoleAndRedirect();
  }

  Future<void> _checkRoleAndRedirect() async {
    try {
      final doc = await firestore.collection('admins').doc(widget.user.uid).get();
      if (!mounted) return;

      if (!doc.exists || doc.data()?['role'] == null) {
        await FirebaseAuth.instance.signOut();
        _navigateTo(AdminWelcomeScreen());
        return;
      }

      final role = doc.data()!['role'] as String;
      final Widget destination = switch (role) {
        'super' => const SuperAdminDashboard(),
        'admin' => const AdminDashboardScreen(),
        _ => AdminWelcomeScreen(),
      };

      if (role != 'super' && role != 'admin') {
        await FirebaseAuth.instance.signOut();
      }

      _navigateTo(destination);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _navigateTo(Widget page) {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => page),
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}