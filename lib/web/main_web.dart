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

// Global Firestore instance pointing to 'daligas' database
final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'daligas',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────
  // Load Google Maps JS only ONCE (prevents duplicate loading warnings)
  // ──────────────────────────────
  if (kIsWeb) {
    final existing = html.document.querySelector(
      'script[src*="maps.googleapis.com"]',
    );
    if (existing == null) {
      final script = html.ScriptElement()
        ..src =
            "https://maps.googleapis.com/maps/api/js?key=AIzaSyAVDDHYb29rt4io-HI0Uq6vfv_GAnlDLlw&libraries=places&loading=async"
        ..async = true
        ..defer = true;
      html.document.head!.append(script);
    }
  }

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Force Singapore region for Cloud Functions
  FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  // Enable persistent auth on web
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  runApp(const MyWebApp());
}

class MyWebApp extends StatelessWidget {
  const MyWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DALIGAS Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AuthGate(),
      // Routes no longer needed — we use pushAndRemoveUntil now
    );
  }
}

// ────────────────────────────────────────────────
// FIXED AuthGate: No more FutureBuilder<Widget>
// Safe navigation, no engine crashes on Web
// ────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == null) {
          return AdminWelcomeScreen();
        }

        return _RoleChecker(user: snapshot.data!);
      },
    );
  }
}

// Private widget that safely checks role and navigates
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

      final data = doc.data();
      if (!doc.exists || data == null || data['role'] == null) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        _navigateTo(AdminWelcomeScreen());
        return;
      }

      final role = data['role'] as String;

      final Widget destination = switch (role) {
        'super_admin' => const SuperAdminDashboard(),
        'admin' => const AdminDashboardScreen(),
        _ => AdminWelcomeScreen(), // fallback + sign out
      };

      if (role != 'super_admin' && role != 'admin') {
        await FirebaseAuth.instance.signOut();
      }

      _navigateTo(destination);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Auth error: $e")),
        );
      }
    }
  }

  // Safe navigation with tiny delay — fixes "disposed EngineFlutterView"
  Future<void> _navigateTo(Widget page) async {
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}