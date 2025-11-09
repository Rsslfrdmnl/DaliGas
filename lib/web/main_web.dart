import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/firebase_options.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart'; // ✅ Has AdminLoginPage

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
        '/admin-login': (_) => AdminWelcomeScreen(),
      },
    );
  }
}

/// ✅ AuthGate now only handles login
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<String?> _getRole(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();
    if (doc.exists) {
      return doc['role']; // "super" or "sub"
    }
    return null;
  }

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

        final user = snapshot.data;
        if (user == null) {
          return AdminWelcomeScreen(); // Not logged in → show login
        }

        // For now, always redirect to AdminLoginPage after login
        return AdminWelcomeScreen();
      },
    );
  }
}