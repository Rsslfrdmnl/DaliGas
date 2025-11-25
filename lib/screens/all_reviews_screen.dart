import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/main_mobile.dart';

class AllReviewsScreen extends StatefulWidget {
  final String productId;
  const AllReviewsScreen({super.key, required this.productId});

  @override
  State<AllReviewsScreen> createState() => _AllReviewsScreenState();
}

class _AllReviewsScreenState extends State<AllReviewsScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;

  // ── TOGGLE LIKE / DISLIKE ON REVIEW ─────────────────────────────────────
  Future<void> _toggleReaction(String reviewId, bool isLike) async {
  if (_user == null) return;

  final reactionRef = firestore
      .collection('products')
      .doc(widget.productId)
      .collection('reviews')
      .doc(reviewId)
      .collection('reactions')
      .doc(_user!.uid);

  final reviewRef = firestore
      .collection('products')
      .doc(widget.productId)
      .collection('reviews')
      .doc(reviewId);

  await firestore.runTransaction((tx) async {
    final snap = await reactionRef.get();
    final current = snap.data()?['type'] as String?;

    if (current == (isLike ? 'like' : 'dislike')) {
      // REMOVE REACTION
      tx.delete(reactionRef);
      tx.update(reviewRef, {
        isLike ? 'likeCount' : 'dislikeCount': FieldValue.increment(-1),
      });
    } else {
      // ADD OR SWITCH REACTION
      tx.set(reactionRef, {
        'type': isLike ? 'like' : 'dislike',
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final updates = <String, dynamic>{};

      if (current == null) {
        // First time reacting
        updates[isLike ? 'likeCount' : 'dislikeCount'] = FieldValue.increment(1);
      } else if (current == 'like' && !isLike) {
        // Switching from like → dislike
        updates['likeCount'] = FieldValue.increment(-1);
        updates['dislikeCount'] = FieldValue.increment(1);
      } else if (current == 'dislike' && isLike) {
        // Switching from dislike → like
        updates['dislikeCount'] = FieldValue.increment(-1);
        updates['likeCount'] = FieldValue.increment(1);
      }

      if (updates.isNotEmpty) {
        tx.update(reviewRef, updates);
      }
    }
  });
}

  // ── REPORT REVIEW ─────────────────────────────────────────────
  Future<void> _reportReview(String reviewId) async {
    if (_user == null) return;

    await firestore.collection('reports').add({
      'type': 'review',
      'productId': widget.productId,
      'reviewId': reviewId,
      'reporterId': _user!.uid,
      'reason': 'Inappropriate',
      'timestamp': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review reported')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2236),
        title: const Text('All Reviews', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('products')
            .doc(widget.productId)
            .collection('reviews')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No reviews yet.', style: TextStyle(color: Colors.white70)),
            );
          }

          final reviews = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            itemBuilder: (context, i) {
              final review = reviews[i];
              final reviewId = review.id;
              final rating = (review['rating'] ?? 0).toDouble();
              final reviewText = review['review'] ?? '';
              final timestamp = review['createdAt'] as Timestamp?;
              final date = timestamp?.toDate();
              final dateStr = date != null
                  ? '${date.month}/${date.day}/${date.year}'
                  : 'Just now';

              final likeCount = (review['likeCount'] ?? 0) as int;
              final dislikeCount = (review['dislikeCount'] ?? 0) as int;

              return FutureBuilder<DocumentSnapshot>(
                future: firestore
                    .collection('users')
                    .doc(review['userId'])
                    .get(),
                builder: (context, userSnapshot) {
                  final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                  final username = userData?['username'] ?? 'Anonymous';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // USER + RATING
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  username,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF0D2236),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Row(
                                children: List.generate(
                                  5,
                                  (index) => Icon(
                                    index < rating.round() ? Icons.star : Icons.star_border,
                                    color: Colors.amber,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // REVIEW TEXT
                          if (reviewText.isNotEmpty)
                            Text(
                              reviewText,
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          if (reviewText.isNotEmpty) const SizedBox(height: 4),

                          // DATE
                          Text(
                            dateStr,
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                          const SizedBox(height: 8),

                          // ── LIKE / DISLIKE + REPORT (NO OVERFLOW) ─────────────────────────────────────
                          Row(
                            children: [
                              // LIKE + DISLIKE (natural width)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // LIKE
                                  StreamBuilder<DocumentSnapshot>(
                                    stream: firestore
                                        .collection('products')
                                        .doc(widget.productId)
                                        .collection('reviews')
                                        .doc(reviewId)
                                        .collection('reactions')
                                        .doc(_user?.uid)
                                        .snapshots(),
                                    builder: (context, snap) {
                                      final type = (snap.data?.data() as Map<String, dynamic>?)?['type'];
                                      final isLiked = type == 'like';

                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                                              color: isLiked ? Colors.blue : Colors.grey,
                                              size: 20,
                                            ),
                                            onPressed: _user == null
                                                ? null
                                                : () => _toggleReaction(reviewId, true),
                                            constraints: const BoxConstraints(), // Remove min size
                                          ),
                                          Text('$likeCount', style: const TextStyle(fontSize: 13)),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // DISLIKE
                                  StreamBuilder<DocumentSnapshot>(
                                    stream: firestore
                                        .collection('products')
                                        .doc(widget.productId)
                                        .collection('reviews')
                                        .doc(reviewId)
                                        .collection('reactions')
                                        .doc(_user?.uid)
                                        .snapshots(),
                                    builder: (context, snap) {
                                      final type = (snap.data?.data() as Map<String, dynamic>?)?['type'];
                                      final isDisliked = type == 'dislike';

                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                                              color: isDisliked ? Colors.red : Colors.grey,
                                              size: 20,
                                            ),
                                            onPressed: _user == null
                                                ? null
                                                : () => _toggleReaction(reviewId, false),
                                            constraints: const BoxConstraints(),
                                          ),
                                          Text('$dislikeCount', style: const TextStyle(fontSize: 13)),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),

                              const Spacer(),

                              // REPORT
                              TextButton.icon(
                                onPressed: () => _reportReview(reviewId),
                                icon: const Icon(Icons.flag_outlined, size: 16),
                                label: const Text('Report', style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}