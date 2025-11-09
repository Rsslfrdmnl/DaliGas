import 'dart:io';
import 'dart:async'; // ← ADD
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/screens/account_screen.dart';
import 'package:daligas/screens/cart_screen.dart' as cart;
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/messages_screen.dart';
import 'package:daligas/screens/purchases_screen.dart';

class HelpScreen extends StatefulWidget {
  final int currentIndex;
  const HelpScreen({super.key, this.currentIndex = 3});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isSubmitting = false;

  // ── DOUBLE BACK TO EXIT (YOUR CHOICE: KEEP) ───────────
  DateTime? _lastBackPress;
  static const int _backPressTimeout = 2;

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: _backPressTimeout)) {
      _lastBackPress = now;
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2), backgroundColor: Colors.black87),
      );
      return false;
    }
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else {
      exit(0); // ← YOUR CHOICE: KEEP
    }
    return true;
  }

  // ── DEBOUNCED SEARCH ───────────────────────────────
  Timer? _debounce;
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _messageController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchText = _searchController.text);
    });
  }

  // ── FAQ DATA ───────────────────────────────────────
  final List<Map<String, dynamic>> _faqData = [
    {
      'category': 'Orders & Delivery',
      'faqs': [
        {
          'q': 'How do I place an order?',
          'a': 'You can place an order directly from the Home screen, your cart, and purchases by selecting your LPG product and confirming your delivery address.'
        },
        {
          'q': 'What should I do if my delivery is late?',
          'a': 'If your delivery is delayed, please check the status in the Purchases tab or contact support via the Messages screen.'
        },
      ]
    },
    {
      'category': 'Payments & Billing',
      'faqs': [
        {
          'q': 'What payment methods are accepted?',
          'a': 'We accept Cash on Delivery and E-wallet payments.'
        },
        {
          'q': 'Why was my payment declined?',
          'a': 'Please make sure your account has sufficient balance and try again. If the issue persists, contact your payment provider.'
        },
      ]
    },
    {
      'category': 'Account & Settings',
      'faqs': [
        {
          'q': 'How do I update my address?',
          'a': 'Go to your Account page, click “My Profile”, and tap “Manage Address” to update your delivery details.'
        },
        {
          'q': 'How do I reset my password?',
          'a': 'From the login screen, tap “Forgot Password?” and follow the instructions sent to your email.'
        },
      ]
    },
  ];

  Future<void> _submitInquiry() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your message.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('help_inquiries').add({
        'uid': user?.uid,
        'email': user?.email,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _messageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your inquiry has been submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredFaqs = _faqData.map((category) {
      final filteredQuestions = (category['faqs'] as List)
          .where((faq) =>
              faq['q'].toString().toLowerCase().contains(_searchText.toLowerCase()) ||
              faq['a'].toString().toLowerCase().contains(_searchText.toLowerCase()))
          .toList();
      return {
        'category': category['category'],
        'faqs': filteredQuestions,
      };
    }).where((cat) => (cat['faqs'] as List).isNotEmpty).toList();

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF052238),
        appBar: AppBar(
          backgroundColor: const Color(0xFF052238),
          elevation: 0,
          titleSpacing: -8,
          automaticallyImplyLeading: false,
          leading: const SizedBox.shrink(),
          title: const Text('Help & Support', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const cart.CartScreen())),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Colors.white)),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How can we assist you today?', style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search FAQs...',
                  hintStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    if (filteredFaqs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('No FAQs found.', style: TextStyle(color: Colors.white70))),
                      ),
                    for (var category in filteredFaqs) _faqCard(category['category'], category['faqs']),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white54),
                    const SizedBox(height: 12),
                    const Text('Need more help?', style: TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _messageController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Type your message here...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitInquiry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Submit Inquiry', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            currentIndex: widget.currentIndex,
            selectedItemColor: const Color(0xFF0D2236),
            unselectedItemColor: Colors.black,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            onTap: (index) {
              if (index == widget.currentIndex) return;
              switch (index) {
                case 0:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const HomeScreen(), transitionDuration: Duration.zero));
                  break;
                case 1:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const MessagesScreen(), transitionDuration: Duration.zero));
                  break;
                case 2:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const PurchasesScreen(currentIndex: 2), transitionDuration: Duration.zero));
                  break;
                case 3:
                  break;
                case 4:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AccountScreen(currentIndex: 4), transitionDuration: Duration.zero));
                  break;
              }
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), activeIcon: Icon(Icons.shopping_bag, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.help_outline), activeIcon: Icon(Icons.help, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person, color: Color(0xFF0D2236)), label: ''),
            ],
          ),
        ),
      ),
    );
  }

  Widget _faqCard(String title, List faqs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        children: [
          for (var faq in faqs)
            ListTile(
              title: Text(faq['q'], style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(faq['a']),
            ),
        ],
      ),
    );
  }
}