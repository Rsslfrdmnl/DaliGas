import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/screens/signin_screen.dart';

class CreateUsernameScreen extends StatefulWidget {
  final String userId;

  const CreateUsernameScreen({super.key, required this.userId});

  @override
  State<CreateUsernameScreen> createState() => _CreateUsernameScreenState();
}

class _CreateUsernameScreenState extends State<CreateUsernameScreen> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isChecking = false;
  bool _isAvailable = false;
  String _message = '';

  Future<void> _checkUsername(String username) async {
    if (username.isEmpty) {
      setState(() {
        _message = '';
        _isAvailable = false;
      });
      return;
    }

    setState(() => _isChecking = true);

    final result = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .get();

    setState(() {
      _isChecking = false;
      if (result.docs.isEmpty) {
        _isAvailable = true;
        _message = '✅ Username available';
      } else {
        _isAvailable = false;
        _message = '❌ Username already taken';
      }
    });
  }

  Future<void> _saveUsername() async {
    if (!_isAvailable) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .set({
      'username': _usernameController.text.trim(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D2236),
        title: const Text(
          'Username Created!',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your username has been saved successfully.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SignInScreen()),
              );
            },
            child: const Text(
              'OK',
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Create a Username',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Choose a unique username for your account.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _usernameController,
                onChanged: (value) => _checkUsername(value.trim()),
                decoration: const InputDecoration(
                  labelText: 'Username',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              if (_message.isNotEmpty)
                Center(
                  child: Text(
                    _message,
                    style: TextStyle(
                      color: _isAvailable ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 40),
              Center(
                child: ElevatedButton(
                  onPressed: _isAvailable ? _saveUsername : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isAvailable ? Colors.white : Colors.grey.shade500,
                    foregroundColor: const Color(0xFF0D2236),
                    minimumSize: const Size(200, 50),
                  ),
                  child: _isChecking
                      ? const CircularProgressIndicator(
                          color: Color(0xFF0D2236),
                        )
                      : const Text('Save Username'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
