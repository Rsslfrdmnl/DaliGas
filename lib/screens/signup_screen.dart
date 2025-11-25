import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/screens/signin_screen.dart';
import 'package:daligas/screens/terms_screen.dart';
import 'package:daligas/screens/privacy_screen.dart';
import 'package:daligas/main_mobile.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  Timer? _usernameDebounce;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameDebounce?.cancel();
    super.dispose();
  }

  // ========================================
  // MAIN SIGN-UP FLOW WITH OTP FALLBACK
  // ========================================
  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();
    final fullName = _fullNameController.text.trim();

    try {
      // === Step 1: Try phone verification (with skip fallback) ===
      final bool phoneVerified = await _tryPhoneVerification(phone);

      // === Step 2: Create user (with or without phone link) ===
      User user;
      if (phoneVerified && FirebaseAuth.instance.currentUser != null) {
        user = FirebaseAuth.instance.currentUser!;
      } else {
        // Create with email/password only
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        user = cred.user!;
      }

      // === Step 3: Save to Firestore ===
      await firestore.collection('users').doc(user.uid).set({
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'phoneVerified': phoneVerified,
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // === Step 4: Ask for username ===
      if (mounted) {
        if (!phoneVerified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Phone not verified. Some features may be limited.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await _askForUsername(user);
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Sign up failed');
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========================================
  // PHONE VERIFICATION WITH SKIP OPTION
  // ========================================
  Future<bool> _tryPhoneVerification(String phone) async {
    if (phone.isEmpty) return false;

    final formattedPhone = _formatPhoneForFirebase(phone);
    final completer = Completer<bool>();

    bool codeSent = false;
    String? verificationId;

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: formattedPhone,
      verificationCompleted: (credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
        completer.complete(true);
      },
      verificationFailed: (e) {
        if (kDebugMode) print('OTP verification failed: $e');
        completer.complete(false);
      },
      codeSent: (vid, _) {
        verificationId = vid;
        codeSent = true;
        completer.complete(false); // Let dialog handle
      },
      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 30),
    );

    final bool autoVerified = await completer.future;
    if (autoVerified) return true;
    if (!codeSent) return false;

    // Show OTP dialog with "Skip"
    final smsCode = await _showOTPDialogWithSkip();
    if (smsCode == null) return false; // User skipped

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId!,
        smsCode: smsCode,
      );
      await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
      return true;
    } catch (e) {
      if (kDebugMode) print('Invalid OTP: $e');
      _showError('Invalid OTP. Proceeding without phone verification.');
      return false;
    }
  }

  String _formatPhoneForFirebase(String phone) {
    String formatted = phone.trim();
    if (formatted.startsWith('0')) {
      formatted = '+63${formatted.substring(1)}';
    } else if (formatted.startsWith('63')) {
      formatted = '+$formatted';
    } else if (!formatted.startsWith('+')) {
      formatted = '+63$formatted';
    }
    return formatted;
  }

  // ========================================
  // OTP DIALOG WITH "SKIP" BUTTON
  // ========================================
  Future<String?> _showOTPDialogWithSkip() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D2236),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Verify Phone', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the 6-digit code sent to your phone',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                labelText: 'OTP Code',
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null), // Skip
            child: const Text('Skip', style: TextStyle(color: Colors.orange)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            child: const Text('Verify', style: TextStyle(color: Color(0xFF0D2236))),
          ),
        ],
      ),
    );
  }

  // ========================================
  // USERNAME DIALOG WITH AVAILABILITY
  // ========================================
  Future<void> _askForUsername(User user) async {
    final controller = TextEditingController();
    String? status;
    bool isChecking = false;
    bool isAvailable = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF0D2236),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Choose Username', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Username',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (value) {
                  final username = value.trim();
                  if (username.isEmpty) {
                    setStateDialog(() {
                      status = null;
                      isAvailable = false;
                    });
                    return;
                  }

                  _usernameDebounce?.cancel();
                  _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
                    setStateDialog(() => isChecking = true);
                    final exists = await _usernameExists(username);
                    setStateDialog(() {
                      isChecking = false;
                      status = exists ? 'Username taken' : 'Available';
                      isAvailable = !exists;
                    });
                  });
                },
              ),
              const SizedBox(height: 12),
              if (isChecking) const CircularProgressIndicator(color: Colors.white),
              if (status != null && !isChecking)
                Text(
                  status!,
                  style: TextStyle(
                    color: isAvailable ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: isAvailable
                  ? () async {
                      await firestore
                          .collection('users')
                          .doc(user.uid)
                          .set({'username': controller.text.trim()}, SetOptions(merge: true));
                      if (mounted) {
                        Navigator.pop(context);
                        _showSuccessAndRedirect();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isAvailable ? Colors.white : Colors.grey,
                foregroundColor: const Color(0xFF0D2236),
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _usernameExists(String username) async {
    final collections = ['users', 'employees'];
    for (final col in collections) {
      final snap = await firestore
          .collection(col)
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return true;
    }
    return false;
  }

  void _showSuccessAndRedirect() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D2236),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Success!', style: TextStyle(color: Colors.white)),
        content: const Text('Account created successfully.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SignInScreen()),
              );
            },
            child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ========================================
  // UI BUILD
  // ========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Sign Up', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 30),

                _buildInput(_fullNameController, 'Full Name', validator: (v) => v!.isEmpty ? 'Required' : null),
                const SizedBox(height: 20),
                _buildInput(_emailController, 'Email', keyboard: TextInputType.emailAddress, validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) return 'Invalid email';
                  return null;
                }),
                const SizedBox(height: 20),
                _buildInput(_phoneController, 'Phone Number', keyboard: TextInputType.phone, validator: (v) => v!.isEmpty ? 'Required' : null),
                const SizedBox(height: 20),
                _buildPasswordField(
                  _passwordController,
                  'Password',
                  _obscurePassword,
                  () => setState(() => _obscurePassword = !_obscurePassword),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (!RegExp(r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[!@#\$&*~]).{8,}$').hasMatch(v)) {
                      return '8+ chars, upper, lower, number, symbol';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _buildPasswordField(
                  _confirmPasswordController,
                  'Confirm Password',
                  _obscureConfirmPassword,
                  () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  validator: (v) {
                    if (v != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 30),

                ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0D2236),
                    minimumSize: const Size(200, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Color(0xFF0D2236))
                      : const Text('Sign Up', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
                const Text('By signing up, you agree to our Terms and Privacy Policy', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsScreen())),
                      child: const Text('Terms', style: TextStyle(color: Colors.blueAccent)),
                    ),
                    const Text(' | ', style: TextStyle(color: Colors.white70)),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen())),
                      child: const Text('Privacy', style: TextStyle(color: Colors.blueAccent)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, {TextInputType? keyboard, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white30)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white)),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String label, bool obscure, VoidCallback toggle, {String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white30)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white)),
        suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white70), onPressed: toggle),
      ),
      validator: validator,
    );
  }
}