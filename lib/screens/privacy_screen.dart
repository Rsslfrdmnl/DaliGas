import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      body: SafeArea(
        child: Column(
          children: [
            // Top AppBar-like section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Main content container
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'At Dali Gas, we value your privacy. This Privacy Policy explains how we collect, use, and protect your information when you use our app.',
                        style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Divider(color: Colors.black26),
                      SizedBox(height: 20),

                      SectionTitle('1. Information We Collect'),
                      SectionText(
                        '• Personal Information: Name, phone number, email, address, and payment details.\n'
                        '• Usage Information: App activity, preferences, and device details.\n'
                        '• Location Data: To provide accurate delivery services (with your permission).',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('2. How We Use Your Information'),
                      SectionText(
                        '• To process and deliver your gas orders.\n'
                        '• To communicate updates, promotions, and service reminders.\n'
                        '• To improve our services and app features.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('3. Sharing of Information'),
                      SectionText(
                        '• We may share your information with delivery partners and payment processors to fulfill your order.\n'
                        '• We do not sell your personal data to third parties.\n'
                        '• We may disclose information if required by law.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('4. Data Protection'),
                      SectionText(
                        '• We implement reasonable security measures to protect your data.\n'
                        '• However, no method of transmission or storage is 100% secure.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('5. Your Rights'),
                      SectionText(
                        '• You may access, update, or request deletion of your personal data.\n'
                        '• You may opt out of marketing communications at any time.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('6. Retention of Data'),
                      SectionText(
                        '• We retain your information only as long as necessary for business and legal purposes.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('7. Updates to This Policy'),
                      SectionText(
                        '• We may revise this Privacy Policy from time to time. Updates will be posted in the app.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('8. Contact Us'),
                      SectionText(
                        'If you have questions about our Terms or Privacy Policy, you may contact us at:\n'
                        '📧 daligas@gmail.com\n'
                        '📞 +63 921 861 8380',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0D2236),
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
    );
  }
}

class SectionText extends StatelessWidget {
  final String text;
  const SectionText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.black87,
        fontSize: 14,
        height: 1.5,
      ),
    );
  }
}
