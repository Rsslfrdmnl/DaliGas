import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with back arrow and title
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
                    'Terms & Conditions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable white content box
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
                        'Welcome to Dali Gas. By using our app and services, you agree to the following Terms and Conditions. Please read them carefully before proceeding.',
                        style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.5),
                      ),
                      SizedBox(height: 20),
                      Divider(color: Colors.black26),
                      SizedBox(height: 20),

                      SectionTitle('1. Acceptance of Terms'),
                      SectionText(
                        'By accessing or using the Dali Gas app, you agree to be bound by these Terms. If you do not agree, please discontinue use immediately.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('2. Services Provided'),
                      SectionText(
                        'Dali Gas provides a platform to order and deliver LPG products to customers through verified suppliers and delivery partners.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('3. User Responsibilities'),
                      SectionText(
                        '• Provide accurate and up-to-date information.\n'
                        '• Keep your account credentials secure.\n'
                        '• Use the app only for lawful purposes.\n'
                        '• Report any unauthorized access immediately.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('4. Orders and Payments'),
                      SectionText(
                        '• Orders are confirmed once payment is successfully processed.\n'
                        '• Prices may change depending on market conditions.\n'
                        '• Refunds are subject to our refund policy and management approval.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('5. Delivery Policy'),
                      SectionText(
                        '• Delivery times are estimates and may vary.\n'
                        '• Dali Gas and its partners are not liable for delays due to unforeseen circumstances (e.g., traffic, weather, etc.).',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('6. Limitation of Liability'),
                      SectionText(
                        'Dali Gas shall not be held liable for indirect, incidental, or consequential damages arising from the use of our app or services.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('7. Account Termination'),
                      SectionText(
                        'We reserve the right to suspend or terminate accounts that violate our policies or misuse our services.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('8. Changes to Terms'),
                      SectionText(
                        'We may update these Terms & Conditions from time to time. Continued use of the app after updates means you accept the new terms.',
                      ),
                      SizedBox(height: 16),

                      SectionTitle('9. Contact Us'),
                      SectionText(
                        'If you have questions regarding these Terms, please reach out to us at:\n'
                        '📧 [Insert Support Email]\n'
                        '📞 [Insert Hotline Number]',
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

// Reusable section components
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
