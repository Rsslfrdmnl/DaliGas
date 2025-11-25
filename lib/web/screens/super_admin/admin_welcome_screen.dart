import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/web/main_web.dart';

// Import your dashboard screens
import 'super_dashboard_screen.dart';
import 'package:daligas/web/screens/sub_admin/admin_dashboard_screen.dart';

class AdminWelcomeScreen extends StatefulWidget {
  @override
  _AdminWelcomeScreenState createState() => _AdminWelcomeScreenState();
}

class _AdminWelcomeScreenState extends State<AdminWelcomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool loading = false;

  // The login logic – unchanged
  Future<void> _login() async {
  if (loading) return; // prevent double tap

  setState(() => loading = true);

  try {
    // 1. Firebase Auth login
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );

    // 2. Firestore role check
    final uid = userCredential.user!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(uid)
        .get();

    // Critical: Check if widget is still mounted after await!
    if (!mounted) return;

    if (!doc.exists || !doc.data()!.containsKey('role')) {
      throw Exception("No role assigned. Contact system administrator.");
    }

    final role = doc['role'] as String;

    // Safe to use context now
    if (role == "super") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SuperAdminDashboard()),
      );
    } else if (role == "admin") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminDashboardScreen()),
      );
    } else {
      throw Exception("Invalid role detected.");
    }
  } catch (e) {
    // Also check mounted before showing SnackBar!
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Login failed: ${e.toString()}"),
        backgroundColor: Colors.red,
      ),
    );
  } finally {
    // Only update loading if still mounted
    if (mounted) {
      setState(() => loading = false);
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          width: 380,
          decoration: BoxDecoration(
            color: const Color(0xFF0D2236),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/daligas_logo.png',
                    height: 120,
                    width: 120,
                  ),
                  Transform.translate(
                    offset: const Offset(-15, 0),
                    child: const Text(
                      'DALI GAS',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Email field – submit on Enter
              TextField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  hintText: "Email",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Password field – submit on Enter
              TextField(
                controller: _passwordController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!loading) _login();
                },
                decoration: const InputDecoration(
                  hintText: "Password",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Login button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size(double.infinity, 45),
                ),
                onPressed: loading ? null : _login,
                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Login",
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}