import 'package:flutter/material.dart';
import 'package:daligas/screens/signup_screen.dart';
import 'package:daligas/screens/signin_screen.dart';
import 'package:daligas/screens/terms_screen.dart';
import 'package:daligas/screens/privacy_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFF0D2236),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/daligas_logo.png',
                height: 150,
                width: 150,
              ),
              const SizedBox(height: 20),
              const Text(
                'DALI GAS',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Need Gas? Dali lang 'yan with Dali Gas!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SignUpScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: null,
                  foregroundColor: const Color(0xFF1E2A44),
                  minimumSize: const Size(200, 50),
                ),
                child: const Text('Sign Up'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SignInScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2A44),
                  foregroundColor: null,
                  minimumSize: const Size(200, 50),
                  side: const BorderSide(color: Colors.white),
                ),
                child: const Text('Sign In'),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TermsScreen()),
                      );
                    },
                    child: const Text(
                      'Terms',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                  const Text(
                    ' | ',
                    style: TextStyle(color: Colors.white),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                      );
                    },
                    child: const Text(
                      'Privacy',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}