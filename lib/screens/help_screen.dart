import 'dart:io';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/screens/account_screen.dart';
import 'package:daligas/screens/cart_screen.dart' as cart;
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/messages_screen.dart';
import 'package:daligas/screens/purchases_screen.dart';
import 'package:daligas/main_mobile.dart';

class HelpScreen extends StatefulWidget {
  final int currentIndex;
  const HelpScreen({super.key, this.currentIndex = 3});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final TextEditingController _searchController = TextEditingController();
  final User? _user = FirebaseAuth.instance.currentUser;

  // DEBOUNCED SEARCH
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
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchText = _searchController.text);
    });
  }

  // REUSABLE REPORT DIALOG (SAME AS IN COMMENTS)
  Future<void> _showReportDialog() async {
    final List<String> reportTypes = ['Comment', 'Reply', 'Chat', 'Review', 'Bug', 'Order Issue', 'Payment Problem', 'Delivery', 'Others'];
    final List<String> reasons = [
      "Inappropriate or offensive content",
      "Spam or advertisement",
      "Harassment or bullying",
      "Contains personal information",
      "Hate speech or discrimination",
      "Misleading or false information",
      "App crash or bug",
      "Payment failed",
      "Delivery delayed",
      "Wrong item received",
      "Other issue",
    ];

    String? selectedType;
    String? selectedReason;
    final detailsController = TextEditingController();
    final reasonKey = GlobalKey();
    final descriptionKey = GlobalKey();

    final result = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.flag, color: Colors.red),
              SizedBox(width: 12),
              Text('Submit a Report', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.7,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What are you reporting?', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    hint: const Text('Select report type'),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    items: reportTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) {
                      setStateDialog(() => selectedType = val);
                      Future.delayed(const Duration(milliseconds: 300), () {
                        Scrollable.ensureVisible(reasonKey.currentContext!, duration: const Duration(milliseconds: 400));
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(key: reasonKey),
                  ...reasons.map((r) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: selectedReason == r ? Colors.red.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selectedReason == r ? Colors.red.shade400 : Colors.transparent, width: 1.5),
                        ),
                        child: RadioListTile<String>(
                          dense: true,
                          title: Text(r, style: const TextStyle(fontSize: 15)),
                          value: r,
                          groupValue: selectedReason,
                          activeColor: Colors.red.shade600,
                          onChanged: (val) {
                            setStateDialog(() => selectedReason = val);
                            Future.delayed(const Duration(milliseconds: 300), () {
                              Scrollable.ensureVisible(descriptionKey.currentContext!, duration: const Duration(milliseconds: 500));
                            });
                          },
                        ),
                      )),

                  const SizedBox(height: 20),
                  const Text('Description (optional but recommended)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(key: descriptionKey),
                  TextField(
                    controller: detailsController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Tell us more about the issue...',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: (selectedType == null || selectedReason == null)
                  ? null
                  : () => Navigator.pop(ctx, {
                      'type': selectedType!,
                      'reason': selectedReason!,
                      'details': detailsController.text.trim(),
                    }),
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Submit Report'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    final type = result['type']!;
    final reason = result['reason']!;
    final details = result['details']!;
    final content = details.isNotEmpty ? '$reason\n\n$details' : reason;

    // Generate Report ID
    final counterSnap = await firestore.collection('counters').doc('reports').get();
    int nextNum = (counterSnap.exists ? (counterSnap['lastNumber'] ?? 0) : 0) + 1;
    await firestore.collection('counters').doc('reports').set({'lastNumber': nextNum}, SetOptions(merge: true));
    final reportId = 'REP-${nextNum.toString().padLeft(3, '0')}';

    String reporterName = 'Anonymous';
    try {
      final doc = await firestore.collection('users').doc(_user!.uid).get();
      if (doc.exists) {
        reporterName = doc['fullName'] ?? doc['username'] ?? 'Customer';
      }
    } catch (e) {
      debugPrint('Name fetch error: $e');
    }

    await firestore.collection('reports').doc(reportId).set({
      'reportId': reportId,
      'type': type,
      'reporterId': _user?.uid,
      'reporterName': reporterName,
      'reason': reason,
      'content': content,
      'date': DateFormat('MMMM d, yyyy').format(DateTime.now()),
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Report $reportId submitted successfully!', style: const TextStyle(fontWeight: FontWeight.w500))),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // FAQ DATA
  final List<Map<String, dynamic>> _faqData = [
    {
      'category': 'Orders & Delivery',
      'faqs': [
        {'q': 'How do I place an order?', 'a': 'Go to Home → Choose product → Confirm address → Place order.'},
        {'q': 'What if my delivery is late?', 'a': 'Check status in Purchases or report via "Submit Report" below.'},
      ]
    },
    {
      'category': 'Payments & Refunds',
      'faqs': [
        {'q': 'What payment methods do you accept?', 'a': 'Cash on Delivery and E-wallet.'},
        {'q': 'My payment failed, what now?', 'a': 'Try again or report the issue using the form below.'},
      ]
    },
    {
      'category': 'Account & App',
      'faqs': [
        {'q': 'How do I update my address?', 'a': 'Go to Account → Profile → Manage Address.'},
        {'q': 'App is crashing?', 'a': 'Please report the bug using the form below with details.'},
      ]
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filteredFaqs = _faqData.map((category) {
      final filtered = (category['faqs'] as List)
          .where((faq) => faq['q'].toString().toLowerCase().contains(_searchText.toLowerCase()) ||
              faq['a'].toString().toLowerCase().contains(_searchText.toLowerCase()))
          .toList();
      return {'category': category['category'], 'faqs': filtered};
    }).where((cat) => (cat['faqs'] as List).isNotEmpty).toList();

    return WillPopScope(
      onWillPop: () async {
        if (Platform.isAndroid) SystemNavigator.pop();
        else exit(0);
        return true;
      },
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
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Frequently Asked Questions', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search FAQs...',
                  hintStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    if (filteredFaqs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No FAQs found.', style: TextStyle(color: Colors.white70))),
                      ),
                    for (var category in filteredFaqs) _faqCard(category['category'], category['faqs']),

                    const Divider(color: Colors.white54, height: 40),
                    const Text('Still need help?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Text('Report bugs, delivery issues, payment problems, or anything else.', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _showReportDialog,
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Submit a Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
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
            backgroundColor: null,
            currentIndex: widget.currentIndex,
            selectedItemColor: const Color(0xFF0D2236),
            unselectedItemColor: Colors.black,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            onTap: (index) {
              if (index == widget.currentIndex) return;
              switch (index) {
                case 0: Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const HomeScreen(), transitionDuration: Duration.zero)); break;
                case 1: Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const MessagesScreen(), transitionDuration: Duration.zero)); break;
                case 2: Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const PurchasesScreen(currentIndex: 2), transitionDuration: Duration.zero)); break;
                case 4: Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AccountScreen(currentIndex: 4), transitionDuration: Duration.zero)); break;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: ExpansionTile(
        collapsedBackgroundColor: null,
        backgroundColor: null,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0D2236))),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: faqs.map<Widget>((faq) => ListTile(
          title: Text(faq['q'], style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(faq['a'])),
        )).toList(),
      ),
    );
  }
}