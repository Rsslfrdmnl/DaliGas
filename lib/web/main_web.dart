import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/firebase_options.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'package:daligas/web/screens/super_admin/super_dashboard_screen.dart'; // Add this
import 'package:daligas/web/screens/sub_admin/admin_dashboard_screen.dart';     // Add this

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load Google Maps script before Firebase on web
  if (kIsWeb) {
    final script = html.ScriptElement()
      ..src = "https://maps.googleapis.com/maps/api/js?key=AIzaSyAVDDHYb29rt4io-HI0Uq6vfv_GAnlDLlw&libraries=places"
      ..async = true
      ..defer = true;
    html.document.head!.append(script);
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Enable persistence (this ensures login stays after refresh)
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
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AuthGate(),
      routes: {
        '/super-admin-dashboard': (_) => const SuperAdminDashboard(),
        '/admin-dashboard': (_) => const AdminDashboardScreen(),
        '/login': (_) => AdminWelcomeScreen(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Widget> _getHomePage(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      // User exists in auth but not in admins collection → force logout or show error
      await FirebaseAuth.instance.signOut();
      return AdminWelcomeScreen();
    }

    final role = doc['role'] as String?;

    if (role == 'super_admin') {
      return const SuperAdminDashboard();
    } else if (role == 'admin') {
      return const AdminDashboardScreen();
    } else {
      // Unknown role → sign out for safety
      await FirebaseAuth.instance.signOut();
      return AdminWelcomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        // Not logged in → go to welcome/login screen
        if (user == null) {
          return AdminWelcomeScreen();
        }

        // Logged in → fetch role and redirect accordingly
        return FutureBuilder<Widget>(
          future: _getHomePage(user),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (roleSnapshot.hasData) {
              return roleSnapshot.data!;
            }

            // Fallback (should not reach here)
            return AdminWelcomeScreen();
          },
        );
      },
    );
  }
}