import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';  
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/employee_orders_screen.dart';

class PhoneSignInScreen extends StatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  State<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends State<PhoneSignInScreen> {
  late TextEditingController _phoneController;
  late TextEditingController _otpController;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _verificationId;
  bool _codeSent = false;
  bool _isLoading = false;
  bool _canResend = false;
  Timer? _resendTimer;
  int _resendSeconds = 180;

  String? _errorMessage;
  String? _otpErrorMessage;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _otpController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  String formatPhoneNumber(String phone) {
    phone = phone.trim().replaceAll(' ', '');
    if (phone.startsWith('0')) return '+63${phone.substring(1)}';
    if (phone.startsWith('+63')) return phone;
    if (phone.startsWith('63')) return '+$phone';
    return '+63$phone';
  }

  void _startResendTimer() {
    setState(() {
      _canResend = false;
      _resendSeconds = 180;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds == 0) {
        setState(() => _canResend = true);
        timer.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode() async {
    if (_phoneController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter your phone number.');
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    final rawPhone = _phoneController.text.trim();
    final formattedPhone = formatPhoneNumber(rawPhone);
    final formattedDbPhone = rawPhone.startsWith('0')
        ? rawPhone
        : rawPhone.startsWith('+63')
            ? rawPhone.replaceFirst('+63', '0')
            : rawPhone.startsWith('63')
                ? '0${rawPhone.substring(2)}'
                : rawPhone;

    setState(() => _isLoading = true);

    try {
      final userQuery = await _firestore
          .collection('users')
          .where('phone', isEqualTo: formattedDbPhone)
          .limit(1)
          .get();

      final adminQuery = await _firestore
          .collection('admins')
          .where('phone', isEqualTo: formattedDbPhone)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty && adminQuery.docs.isEmpty) {
        setState(() {
          _errorMessage = 'This number is not registered!';
          _isLoading = false;
        });
        return;
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInWithCredential(credential, formattedDbPhone);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              _errorMessage = e.message ?? 'Verification failed.';
              _isLoading = false;
              _codeSent = false;
            });
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _isLoading = false;
              _codeSent = true;
              _errorMessage = null;
            });
          }
          _startResendTimer();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OTP has been sent to your phone.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error sending code. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationId == null || _otpController.text.isEmpty) {
      setState(() => _otpErrorMessage = 'Please enter the OTP code.');
      return;
    }

    setState(() {
      _otpErrorMessage = null;
      _isLoading = true;
    });

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );
      await _signInWithCredential(credential, _phoneController.text.trim());
    } catch (e) {
      setState(() {
        _otpErrorMessage = 'Invalid code or verification failed.';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

Future<void> _signInWithCredential(
    PhoneAuthCredential credential, String rawPhone) async {
  try {
    // Normalize for Firestore lookup (0-prefix)
    final formattedDbPhone = rawPhone.startsWith('0')
        ? rawPhone
        : rawPhone.startsWith('+63')
            ? rawPhone.replaceFirst('+63', '0')
            : rawPhone.startsWith('63')
                ? '0${rawPhone.substring(2)}'
                : rawPhone;

    // ✅ Just sign in with the credential
    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;

    if (user == null) {
      setState(() => _otpErrorMessage = 'Sign-in failed. Try again.');
      return;
    }

    // ✅ Go to Firestore to check role and navigate
    await _navigateAfterLoginByPhone(formattedDbPhone);
  } on FirebaseAuthException catch (e) {
    setState(() => _otpErrorMessage = e.message ?? 'Error signing in.');
  } catch (e) {
    setState(() => _otpErrorMessage = 'Unexpected error occurred.');
  } finally {
    setState(() => _isLoading = false);
  }
}


Future<void> _navigateAfterLoginByPhone(String phone) async {
  String? role;
  String? username;
  Widget? targetScreen;

  final userQuery = await _firestore
      .collection('users')
      .where('phone', isEqualTo: phone)
      .limit(1)
      .get();

  final adminQuery = await _firestore
      .collection('admins')
      .where('phone', isEqualTo: phone)
      .limit(1)
      .get();

  if (userQuery.docs.isNotEmpty) {
    role = userQuery.docs.first.data()['role'];
    username = userQuery.docs.first.data()['username'] ?? 'User';
  } else if (adminQuery.docs.isNotEmpty) {
    role = adminQuery.docs.first.data()['role'];
    username = adminQuery.docs.first.data()['username'] ?? 'Employee';
  }

  if (role == 'user') {
    targetScreen = const HomeScreen();
  } else if (role == 'employee') {
    targetScreen = const EmployeeOrdersScreen();
  } else {
    setState(() => _otpErrorMessage = 'Role not found for this account.');
    return;
  }

  // ✅ Success snackbar
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

  // ✅ Wait a bit before navigating (so the snackbar is visible)
  await Future.delayed(const Duration(seconds: 1));

  if (mounted && targetScreen != null) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => targetScreen!,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    // Your UI stays exactly the same
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2236),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Phone Login',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_codeSent) ...[
              const Text(
                'Enter your registered phone number to receive an OTP for login.',
                style:
                    TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white38),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 40),
              Center(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0D2236),
                    minimumSize: const Size(220, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Color(0xFF0D2236),
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Send Code',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ] else ...[
              const Text(
                'Enter the 6-digit OTP sent to your phone.',
                style:
                    TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'OTP Code',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white38),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              if (_otpErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_otpErrorMessage!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 40),
              Center(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0D2236),
                    minimumSize: const Size(220, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Color(0xFF0D2236),
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Verify Code',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: !_canResend
                    ? Text(
                        "Resend available in $_resendSeconds seconds",
                        style: const TextStyle(color: Colors.white70),
                      )
                    : TextButton(
                        onPressed: _sendCode,
                        child: const Text('Resend Code',
                            style: TextStyle(color: Colors.white)),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
