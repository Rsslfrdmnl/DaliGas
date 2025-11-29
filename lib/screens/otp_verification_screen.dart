import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/employee_orders_screen.dart';
import 'package:daligas/main_mobile.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String email;
  final String password;
  final String phone;
  final String? verificationId;
  final PhoneAuthCredential? autoCredential;

  const OTPVerificationScreen({
    super.key,
    required this.email,
    required this.password,
    required this.phone,
    this.verificationId,
    this.autoCredential,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = firestore;

  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;

  Future<void> _verifyOTP() async {
    try {
      setState(() => _isLoading = true);

      PhoneAuthCredential phoneCredential = widget.autoCredential ??
          PhoneAuthProvider.credential(
            verificationId: widget.verificationId!,
            smsCode: _otpController.text.trim(),
          );

      // Step 1: Create user with email/password
      UserCredential emailUser =
          await _auth.createUserWithEmailAndPassword(
        email: widget.email,
        password: widget.password,
      );

      // Step 2: Link verified phone credential
      await emailUser.user!.linkWithCredential(phoneCredential);

      // Step 3: Ask for username popup
      String? username = await _showUsernameDialog();

      // Step 4: Save user info to Firestore
      await firestore.collection('users').doc(emailUser.user!.uid).set({
        'email': widget.email,
        'phone': widget.phone,
        'username': username ?? '',
        'fullName': '',
        'role': 'customer',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Step 5: Navigate (same routing logic)
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Verification failed')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _showUsernameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set your username'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Enter the OTP sent to your phone'),
            const SizedBox(height: 20),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'OTP Code'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _verifyOTP,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Verify'),
            ),
          ],
        ),
      ),
    );
  }
}
