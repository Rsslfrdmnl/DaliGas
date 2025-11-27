import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/screens/order_success_screen.dart';
import 'package:daligas/screens/home_screen.dart';
import 'dart:async';

class GcashPaymentScreen extends StatefulWidget {
  final String paymentUrl;
  final String orderAmount;
  final String pendingOrderId;

  const GcashPaymentScreen({
    Key? key,
    required this.paymentUrl,
    required this.orderAmount,
    required this.pendingOrderId,
  }) : super(key: key);

  @override
  State<GcashPaymentScreen> createState() => _GcashPaymentScreenState();
}

class _GcashPaymentScreenState extends State<GcashPaymentScreen> {
  late final WebViewController controller;
  bool _isLoading = true;
  Timer? _countdownTimer;
  int _secondsRemaining = 10 * 60; // 10 minutes
  bool _hasNavigated = false; // Prevent double navigation

  @override
  void initState() {
    super.initState();
    _startCountdown();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (request) async {
            final url = request.url.toString().toLowerCase();
            debugPrint("WebView navigating to: $url");

            // === SUCCESS DETECTION ===
            if (url.contains('daligas.app/success') || url.contains('/success')) {
              _cancelTimer();

              if (_hasNavigated || !mounted) return NavigationDecision.prevent;
              _hasNavigated = true;

              // Mark as paid + clear cart
              await Future.wait([
                _markOrderAsPaid(),
                _clearCartFromDevice(),
              ]);

              if (!mounted) return NavigationDecision.prevent;

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderSuccessScreen(orderId: widget.pendingOrderId),
                ),
                (route) => false,
              );
              return NavigationDecision.prevent;
            }

            // === FAILED OR CANCELLED BY USER ===
            if (url.contains('daligas.app/failed') ||
                url.contains('/failed') ||
                url.contains('cancel') ||
                url.contains('declined')) {
              _cancelTimer();

              if (_hasNavigated || !mounted) return NavigationDecision.prevent;
              _hasNavigated = true;

              await _cancelAndReturnToHome("Payment failed or cancelled");
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 0) {
        timer.cancel();
        if (mounted && !_hasNavigated) {
          _cancelAndReturnToHome("Payment time expired (10 minutes)");
        }
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  void _cancelTimer() => _countdownTimer?.cancel();

  Future<void> _clearCartFromDevice() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final cartRef = FirebaseFirestore.instance
          .collection('cart')
          .doc(user.uid)
          .collection('items');

      final snapshot = await cartRef.get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint("Failed to clear cart: $e");
    }
  }

  Future<void> _markOrderAsPaid() async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.pendingOrderId)
          .update({
        'paymentStatus': 'Paid',
        'deliveryStatus': 'Processing',
        'paidAt': FieldValue.serverTimestamp(),
      });
      debugPrint("Order ${widget.pendingOrderId} marked as PAID");
    } catch (e) {
      debugPrint("Failed to update payment status: $e");
      // Don't throw — user already paid via GCash
    }
  }

  Future<void> _cancelAndReturnToHome(String reason) async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _cancelTimer();

    // Cancel order in Firestore
    try {
      final orderRef = FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.pendingOrderId);

      await orderRef.update({
        'deliveryStatus': 'Cancelled',
        'paymentStatus': 'Cancelled',
        'cancelReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      // Return stock
      final orderSnap = await orderRef.get();
      if (orderSnap.exists) {
        final items = orderSnap.data()?['items'] as List<dynamic>? ?? [];
        final batch = FirebaseFirestore.instance.batch();
        final productCollection = FirebaseFirestore.instance.collection('products');

        for (var item in items) {
          final productId = item['productId'] ?? item['id'];
          final qty = (item['quantity'] ?? 1) as int;
          if (productId != null) {
            final productRef = productCollection.doc(productId.toString());
            batch.update(productRef, {'stock': FieldValue.increment(qty)});
          }
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint("Cancellation error: $e");
    }

    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 300));

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason.contains("expired")
            ? "Payment timed out. Your order was cancelled."
            : "Payment failed or was cancelled."),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _handleCancel() async {
    if (_hasNavigated) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.warning_amber, color: Colors.orange, size: 60),
        title: const Text("Cancel Payment?"),
        content: const Text(
          "Your order will be cancelled and items returned to cart.\n\nYou can try paying again later.",
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Continue Paying"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Cancel Order"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _cancelAndReturnToHome("User cancelled payment");
    }
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleCancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GCash Payment'),
          backgroundColor: const Color(0xFF001B33),
          foregroundColor: null,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _handleCancel,
            ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.blue),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _secondsRemaining < 120 ? Colors.red.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _secondsRemaining < 120 ? Colors.red : Colors.orange,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _secondsRemaining < 120 ? Icons.timer_off : Icons.timer,
                  color: _secondsRemaining < 120 ? Colors.red : Colors.orange[700],
                ),
                const SizedBox(width: 12),
                Text(
                  "Complete payment in: $minutes:$seconds",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _secondsRemaining < 120 ? Colors.red : Colors.orange[800],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}