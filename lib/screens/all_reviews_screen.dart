// lib/screens/all_reviews_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:daligas/main_mobile.dart';

class AllReviewsScreen extends StatefulWidget {
  final String productId;
  const AllReviewsScreen({super.key, required this.productId});

  @override
  State<AllReviewsScreen> createState() => _AllReviewsScreenState();
}

class _AllReviewsScreenState extends State<AllReviewsScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;

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
      final snap = await tx.get(reactionRef);
      final current = snap.data()?['type'] as String?;

      if (current == (isLike ? 'like' : 'dislike')) {
        tx.delete(reactionRef);
        tx.update(reviewRef, {
          isLike ? 'likeCount' : 'dislikeCount': FieldValue.increment(-1),
        });
      } else {
        tx.set(reactionRef, {
          'type': isLike ? 'like' : 'dislike',
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final updates = <String, dynamic>{};
        if (current == null) {
          updates[isLike ? 'likeCount' : 'dislikeCount'] = FieldValue.increment(1);
        } else if (current == 'like' && !isLike) {
          updates['likeCount'] = FieldValue.increment(-1);
          updates['dislikeCount'] = FieldValue.increment(1);
        } else if (current == 'dislike' && isLike) {
          updates['dislikeCount'] = FieldValue.increment(-1);
          updates['likeCount'] = FieldValue.increment(1);
        }
        if (updates.isNotEmpty) tx.update(reviewRef, updates);
      }
    });
  }

  // REUSABLE REPORT DIALOG (SAME AS CHAT)
  Future<void> _showReportDialog({
    required String reviewId,
    required String reviewerName,
  }) async {
    final List<String> reportTypes = ['Comment', 'Reply', 'Chat', 'Review', 'Bug', 'Order Issue', 'Payment Problem', 'Delivery', 'Others'];
    final List<String> reasons = [
      "Inappropriate or offensive content",
      "Spam or fake review",
      "Harassment or personal attack",
      "Contains personal information",
      "Misleading or false information",
      "Hate speech or discrimination",
      "Other issue",
    ];

    String? selectedType; // Pre-select "Review"
    String? selectedReason;
    final detailsController = TextEditingController();

    final scrollController = ScrollController();
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
              Text('Report Review', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.7,
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What are you reporting?', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
  value: selectedType,
  hint: const Text('Select report type'), // ← Beautiful hint
  decoration: InputDecoration(
    filled: true,
    fillColor: Colors.grey.shade100,
    hintStyle: TextStyle(color: Colors.grey.shade600),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  ),
  items: reportTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
  onChanged: (val) {
    setStateDialog(() => selectedType = val);
    Future.delayed(const Duration(milliseconds: 300), () {
      Scrollable.ensureVisible(reasonKey.currentContext!, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
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
                              Scrollable.ensureVisible(descriptionKey.currentContext!, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
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
                      hintText: 'Provide more details...',
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
              onPressed: (selectedReason == null) ? null : () => Navigator.pop(ctx, {
                'reason': selectedReason!,
                'details': detailsController.text.trim(),
              }),
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Submit Report'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: null),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    final reason = result['reason']!;
    final details = result['details']!;
    final content = details.isNotEmpty ? '$reason\n\n$details' : reason;

    // Get reporter name
    String reporterName = 'Anonymous';
    try {
      final doc = await firestore.collection('users').doc(_user!.uid).get();
      if (doc.exists) {
        reporterName = doc['fullName'] ?? doc['username'] ?? 'Customer';
      }
    } catch (e) { debugPrint('Name fetch error: $e'); }

    // Generate REP-XXX
    final counterSnap = await firestore.collection('counters').doc('reports').get();
    int nextNum = (counterSnap.exists ? (counterSnap['lastNumber'] ?? 0) : 0) + 1;
    await firestore.collection('counters').doc('reports').set({'lastNumber': nextNum}, SetOptions(merge: true));
    final reportId = 'REP-${nextNum.toString().padLeft(3, '0')}';

    final formattedDate = DateFormat('MMMM d, yyyy').format(DateTime.now());

    // Save full report
    await firestore.collection('reports').doc(reportId).set({
      'reportId': reportId,
      'type': selectedType,
      'reporterId': _user!.uid,
      'reporterName': reporterName,
      'productId': widget.productId,
      'reviewId': reviewId,
      'reviewerName': reviewerName,
      'reason': reason,
      'content': content,
      'date': formattedDate,
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
              Expanded(child: Text('Report submitted!', style: const TextStyle(fontWeight: FontWeight.w500))),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2236),
        title: const Text('All Reviews', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
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
              child: Text('No reviews yet. Be the first!', style: TextStyle(color: Colors.white70, fontSize: 16)),
            );
          }

          final reviews = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            itemBuilder: (context, i) {
              final review = reviews[i];
              final data = review.data() as Map<String, dynamic>;
              final reviewId = review.id;

              final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
              final reviewText = (data['review'] ?? '').toString();
              final timestamp = (data['createdAt'] as Timestamp?)?.toDate();
              final dateStr = timestamp != null
                  ? DateFormat('MMM d, yyyy').format(timestamp)
                  : 'Just now';

              final likeCount = (data['likeCount'] ?? 0) as int;
              final dislikeCount = (data['dislikeCount'] ?? 0) as int;

              // Admin reply
              final adminReply = data['adminReply']?.toString();
              final repliedAt = (data['repliedAt'] as Timestamp?)?.toDate();

              final userId = data['userId'] as String?;

              return FutureBuilder<DocumentSnapshot>(
                future: userId != null
                    ? firestore.collection('users').doc(userId).get()
                    : null,
                builder: (context, userSnapshot) {
                  String username = 'Anonymous';
                  String? photoUrl;

                  if (userSnapshot.hasData && userSnapshot.data!.exists) {
                    final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                    username = userData?['username'] ?? userData?['fullName'] ?? 'Anonymous';
                    photoUrl = userData?['photoURL'] ??
                        userData?['profileImage'] ??
                        userData?['imageUrl']; // supports all common field names
                  }

                  final initials = username.isNotEmpty ? username[0].toUpperCase() : '?';

                  return Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // USER INFO + RATING
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: const Color(0xFF0D2236),
                                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                    ? CachedNetworkImageProvider(photoUrl) as ImageProvider
                                    : null,
                                child: photoUrl == null || photoUrl.isEmpty
                                    ? Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      username,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(fontSize: 12, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: List.generate(5, (i) => Icon(
                                  i < rating.round() ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: 20,
                                )),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // REVIEW TEXT
                          if (reviewText.isNotEmpty)
                            Text(
                              reviewText,
                              style: const TextStyle(fontSize: 14.8, height: 1.5),
                            ),
                          const SizedBox(height: 12),

                          // ADMIN REPLY (if exists)
                          if (adminReply != null && adminReply.trim().isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.green.shade300, width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.support_agent_rounded, color: Colors.green.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Reply from DALI GAS",
                                        style: TextStyle(
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    adminReply.trim(),
                                    style: const TextStyle(fontSize: 14.5, color: Colors.black87),
                                  ),
                                  if (repliedAt != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        "• Replied ${DateFormat('MMM d • hh:mm a').format(repliedAt)}",
                                        style: const TextStyle(fontSize: 11.5, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 12),

                          // LIKE / DISLIKE + REPORT
                          Row(
                            children: [
                              // Like
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
                                  final isLiked = (snap.data?.data() as Map<String, dynamic>?)?['type'] == 'like';
                                  return Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                                            color: isLiked ? Colors.blue : Colors.grey[600]),
                                        onPressed: _user == null ? null : () => _toggleReaction(reviewId, true),
                                      ),
                                      Text('$likeCount', style: const TextStyle(fontSize: 13)),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(width: 16),

                              // Dislike
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
                                  final isDisliked = (snap.data?.data() as Map<String, dynamic>?)?['type'] == 'dislike';
                                  return Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                                            color: isDisliked ? Colors.red : Colors.grey[600]),
                                        onPressed: _user == null ? null : () => _toggleReaction(reviewId, false),
                                      ),
                                      Text('$dislikeCount', style: const TextStyle(fontSize: 13)),
                                    ],
                                  );
                                },
                              ),

                              const Spacer(),

                              TextButton.icon(
                                onPressed: () => _showReportDialog(
                                  reviewId: reviewId,
                                  reviewerName: username,
                                ),
                                icon: const Icon(Icons.flag_outlined, size: 18, color: Colors.red),
                                label: const Text('Report', style: TextStyle(color: Colors.red, fontSize: 13)),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero),
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