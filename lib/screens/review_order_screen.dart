// lib/screens/review_order_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/main_mobile.dart';

class ReviewOrderScreen extends StatefulWidget {
  final String orderId;
  final List<Map<String, dynamic>> items;

  const ReviewOrderScreen({
    super.key,
    required this.orderId,
    required this.items,
  });

  @override
  State<ReviewOrderScreen> createState() => _ReviewOrderScreenState();
}

class _ReviewOrderScreenState extends State<ReviewOrderScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, int> _itemRatings = {};
  final Map<String, TextEditingController> _itemComments = {};
  bool _isSubmitting = false;
  late AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    for (final item in widget.items) {
      final productId = item['productId'] ?? item['id'] as String;
      _itemRatings[productId] = 5;
      _itemComments[productId] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _itemComments.values) {
      controller.dispose();
    }
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        title: const Text('Rate Order'),
        backgroundColor: const Color(0xFF052238),
        foregroundColor: null,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...widget.items.map((item) {
                final productId = item['productId'] ?? item['id'] as String;
                return Card(
                  color: Colors.white10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                item['imageUrl'] ?? '',
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 50,
                                  height: 50,
                                  color: Colors.white24,
                                  child: const Icon(Icons.image,
                                      color: Colors.white54),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item['name'] ?? 'Product',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ⭐ Star Rating
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            5,
                            (i) => IconButton(
                              icon: Icon(
                                i < (_itemRatings[productId] ?? 5)
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                              ),
                              onPressed: () => setState(
                                  () => _itemRatings[productId] = i + 1),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 💬 Review Text Field
                        TextField(
                          controller: _itemComments[productId],
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Write your review...',
                            hintStyle:
                                const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white10,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),

              const SizedBox(height: 24),

              // 🌀 Submit Button with only icon spin
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _isSubmitting || !_hasAnyRating() ? null : _submitReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? RotationTransition(
                          turns: Tween(begin: 0.0, end: 1.0).animate(
                            CurvedAnimation(
                                parent: _spinController, curve: Curves.linear),
                          ),
                          child: const Icon(Icons.sync, color: Colors.white),
                        )
                      : const Text(
                          'Submit Review',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),

          // 🌀 Overlay Spinner (optional, if you still want dim background)
          if (_isSubmitting)
            Container(
              color: Colors.black26,
            ),
        ],
      ),
    );
  }

  bool _hasAnyRating() => _itemRatings.values.any((r) => r > 0);

  Future<void> _submitReview() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSubmitting = true;
      _spinController.repeat();
    });

    final batch = firestore.batch();

    try {
      final userDoc = await firestore
          .collection('users')
          .doc(user.uid)
          .get();
      final username = userDoc['username'] ?? 'Anonymous';

      for (final item in widget.items) {
        final productId = item['productId'] ?? item['id'] as String;
        final itemRating = _itemRatings[productId] ?? 0;
        final reviewText = _itemComments[productId]?.text.trim() ?? '';

        if (itemRating == 0) continue;

        final reviewRef = firestore
            .collection('products')
            .doc(productId)
            .collection('reviews')
            .doc();

        batch.set(reviewRef, {
          'userId': user.uid,
          'userName': username,
          'rating': itemRating,
          'review': reviewText,
          'orderId': widget.orderId,
          'likeCount': 0,
          'dislikeCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Update product rating & count
        final productRef =
            firestore.collection('products').doc(productId);
        await firestore.runTransaction((tx) async {
          final snap = await tx.get(productRef);
          if (!snap.exists) return;

          final data = snap.data()!;
          final currRating = (data['rating'] ?? 0.0).toDouble();
          final currCount = (data['reviewCount'] ?? 0) as int;

          final newCount = currCount + 1;
          final newRating =
              ((currRating * currCount) + itemRating) / newCount;

          tx.update(productRef, {
            'rating': double.parse(newRating.toStringAsFixed(2)),
            'reviewCount': newCount,
          });
        });
      }

      await batch.commit();

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _spinController.stop();
        });
        _showSuccessDialog();
      }
    } catch (e) {
      debugPrint('Review submit error: $e');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _spinController.stop();
        });
        _showErrorDialog(e.toString());
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Review Submitted'),
          ],
        ),
        content: const Text(
          'Thank you for sharing your feedback! Your review helps others make better choices.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child:
                const Text('Okay', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Submission Failed'),
          ],
        ),
        content: Text('Something went wrong:\n$message'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Try Again',
                style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
}
