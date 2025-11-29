import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/services/auth_service.dart';
import 'package:daligas/main_mobile.dart'; // ← This gives us global firestore & saveFcmToken
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/employee_orders_screen.dart';
import 'package:daligas/screens/forgot_password_screen.dart';
import 'package:daligas/screens/phone_signin_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();

    try {
      String? emailToUse;
      String? username;
      String? role;
      String? sourceCollection;

      final isEmail = identifier.contains('@');

      if (isEmail) {
        emailToUse = identifier;
      } else {
        // === 1. Check 'users' collection ===
        final userQuery = await firestore
            .collection('users')
            .where('username', isEqualTo: identifier)
            .limit(1)
            .get();

        if (userQuery.docs.isNotEmpty) {
            final doc = userQuery.docs.first;
            emailToUse = doc['email'];
            username = doc['username'];
            role = doc['role'];
            sourceCollection = 'users';
          } 
        // === 2. Check 'employees' collection ===
        else {
          final empQuery = await firestore
              .collection('employees')
              .where('username', isEqualTo: identifier)
              .limit(1)
              .get();

          if (empQuery.docs.isNotEmpty) {
            final doc = empQuery.docs.first;
            emailToUse = doc['email'];
            username = doc['username'];
            role = doc['role'];
            sourceCollection = 'employees';
          }
        }

        if (emailToUse == null) {
          throw Exception("Username not found. Please try again.");
        }
      }

      // === 3. Sign in with email + password ===
      User? user;
      try {
        user = await _authService.signIn(emailToUse!, password);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password') {
          throw Exception("Incorrect password. Please try again.");
        } else if (e.code == 'user-not-found') {
          throw Exception("No user found with this email or username.");
        } else if (e.code == 'invalid-credential') {
          throw Exception("Incorrect email or password.");
        } else {
          throw Exception("Sign-in failed: ${e.message}");
        }
      }

      if (user == null) throw Exception("Sign-in failed. Please try again.");

      // === 4. Fetch Firestore info if not from username lookup ===
      if (username == null) {
        final userDoc = await firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          username = userDoc['username'];
          role = userDoc['role'];
          sourceCollection = 'users';
        } else {
          final empDoc = await firestore.collection('employees').doc(user.uid).get();
          if (empDoc.exists) {
            username = empDoc['username'];
            role = empDoc['role'];
            sourceCollection = 'employees';
          }
        }
      }

      if (username == null || role == null) {
        throw Exception("User information missing in Firestore.");
      }

      // === 5. Success Message ===
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text('Welcome, $username!',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: const Color(0xFF0D2236),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      );

      await Future.delayed(const Duration(seconds: 1));

      // === 6. Navigate by role ===
      Widget targetScreen;
      if (sourceCollection == 'users' && role == 'user') {
        targetScreen = const HomeScreen();
      } else if (sourceCollection == 'employees' && role == 'employee') {
        targetScreen = const EmployeeOrdersScreen();
      } else {
        throw Exception("Invalid role or collection combination.");
      }

      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => targetScreen,
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );

        // Save FCM token after successful login
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await saveFcmToken(currentUser);
          debugPrint("FCM token saved for ${currentUser.uid}");
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.toString().replaceFirst('Exception: ', ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFF0D2236),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Email or Username
                  TextFormField(
                    controller: _identifierController,
                    decoration: InputDecoration(
                      labelText: 'Email or Username',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF162A41),
                      prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24, width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white, width: 1.5),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) =>
                        (value == null || value.isEmpty)
                            ? 'Please enter your email or username'
                            : null,
                  ),
                  const SizedBox(height: 20),

                  // Password
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF162A41),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24, width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white, width: 1.5),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) =>
                        (value == null || value.isEmpty)
                            ? 'Please enter your password'
                            : null,
                  ),
                  const SizedBox(height: 30),

                  // Sign In Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: null,
                        foregroundColor: const Color(0xFF0D2236),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0D2236),
                              ),
                            )
                          : const Text(
                              'Sign In',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Forgot Password
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                      );
                    },
                    child: const Text('Forgot Password?', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(height: 25),

                  const Text('OR', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 25),

                  // Phone Sign In
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PhoneSignInScreen()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Log in with Phone', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}