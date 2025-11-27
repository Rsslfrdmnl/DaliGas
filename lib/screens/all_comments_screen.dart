import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:daligas/main_mobile.dart';


class AllCommentsScreen extends StatefulWidget {
  final String productId;
  const AllCommentsScreen({super.key, required this.productId});

  @override
  State<AllCommentsScreen> createState() => _AllCommentsScreenState();
}

class _AllCommentsScreenState extends State<AllCommentsScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;

// ── REUSABLE REPORT DIALOG (SAME AS CHAT & REVIEWS) ─────────────────────
  Future<void> _showReportDialog({
    required String commentId,
    String? replyId,
    required String authorName,
  }) async {
    final List<String> reportTypes = ['Comment', 'Reply', 'Chat', 'Review', 'Bug', 'Order Issue', 'Payment Problem', 'Delivery', 'Others'];
    final List<String> reasons = [
      "Inappropriate or offensive content",
      "Spam or advertisement",
      "Harassment or bullying",
      "Contains personal information",
      "Hate speech or discrimination",
      "Misleading or false information",
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
          title: Row(
            children: [
              const Icon(Icons.flag, color: Colors.red),
              const SizedBox(width: 12),
              Text('Report ${replyId == null ? 'Comment' : 'Reply'}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                  hint: const Text('Select report type'), // ← Helpful hint
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
              onPressed: selectedReason == null ? null : () => Navigator.pop(ctx, {
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

    String reporterName = 'Anonymous';
    try {
      final doc = await firestore.collection('users').doc(_user!.uid).get();
      if (doc.exists) {
        reporterName = doc['fullName'] ?? doc['username'] ?? 'Customer';
      }
    } catch (e) {
      debugPrint('Name fetch error: $e');
    }

    final counterSnap = await firestore.collection('counters').doc('reports').get();
    int nextNum = (counterSnap.exists ? (counterSnap['lastNumber'] ?? 0) : 0) + 1;
    await firestore.collection('counters').doc('reports').set({'lastNumber': nextNum}, SetOptions(merge: true));
    final reportId = 'REP-${nextNum.toString().padLeft(3, '0')}';
    final formattedDate = DateFormat('MMMM d, yyyy').format(DateTime.now());

    await firestore.collection('reports').doc(reportId).set({
      'reportId': reportId,
      'type': selectedType,
      'reporterId': _user!.uid,
      'reporterName': reporterName,
      'productId': widget.productId,
      'commentId': commentId,
      'replyId': replyId,
      'authorName': authorName,
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
              Expanded(child: Text('Report $reportId submitted!', style: const TextStyle(fontWeight: FontWeight.w500))),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ── REACTION ─────────────────────────────────────
  Future<void> _toggleReaction(String commentId, bool isLike) async {
    if (_user == null) return;
    final reactionRef = firestore
        .collection('products')
        .doc(widget.productId)
        .collection('comments')
        .doc(commentId)
        .collection('reactions')
        .doc(_user!.uid);

    final commentRef = firestore
        .collection('products')
        .doc(widget.productId)
        .collection('comments')
        .doc(commentId);

    await firestore.runTransaction((tx) async {
      final snap = await tx.get(reactionRef);
      final current = snap.data()?['type'] as String?;

      if (current == (isLike ? 'like' : 'dislike')) {
        tx.delete(reactionRef);
        tx.update(commentRef, {
          isLike ? 'likeCount' : 'dislikeCount': FieldValue.increment(-1),
        });
      } else {
        tx.set(reactionRef, {'type': isLike ? 'like' : 'dislike'}, SetOptions(merge: true));
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
        if (updates.isNotEmpty) tx.update(commentRef, updates);
      }
    });
  }

  // ── REPLY (supports nested replies) ─────────────────────────────────────
  Future<void> _showReplyDialog(String parentCommentId, {String? parentReplyId}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.reply), SizedBox(width: 8), Text('Write a reply')]),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: "Be kind and respectful...",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Post Reply'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    final userDoc = await firestore.collection('users').doc(_user!.uid).get();
    final username = userDoc.data()?['username'] ?? userDoc.data()?['fullName'] ?? 'User';

    final collectionPath = parentReplyId == null
        ? firestore
            .collection('products')
            .doc(widget.productId)
            .collection('comments')
            .doc(parentCommentId)
            .collection('replies')
        : firestore
            .collection('products')
            .doc(widget.productId)
            .collection('comments')
            .doc(parentCommentId)
            .collection('replies')
            .doc(parentReplyId)
            .collection('replies');

    await collectionPath.add({
      'userId': _user!.uid,
      'username': username,
      'text': result,
      'timestamp': FieldValue.serverTimestamp(),
      'parentReplyId': parentReplyId,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2236),
        title: const Text('All Comments', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('products')
            .doc(widget.productId)
            .collection('comments')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No comments yet. Be the first!', style: TextStyle(color: Colors.white70)));
          }

          final comments = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: comments.length,
            itemBuilder: (context, i) {
              final doc = comments[i];
              final data = doc.data() as Map<String, dynamic>;
              final commentId = doc.id;
              final userId = data['userId'] as String?;
              final isOwn = userId == _user?.uid;

              final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
              final dateStr = timestamp != null 
                  ? DateFormat('MMM d, yyyy').format(timestamp) 
                  : 'Just now';

              final likeCount = (data['likeCount'] ?? 0) as int;
              final dislikeCount = (data['dislikeCount'] ?? 0) as int;
              final imageUrls = (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];

              return FutureBuilder<DocumentSnapshot>(
                future: userId != null ? firestore.collection('users').doc(userId).get() : null,
                builder: (context, userSnap) {
                  String username = 'Anonymous';
                  String? photoUrl;
                  if (userSnap.hasData && userSnap.data!.exists) {
                    final u = userSnap.data!.data() as Map<String, dynamic>?;
                    username = u?['username'] ?? u?['fullName'] ?? 'Anonymous';
                    photoUrl = u?['photoURL'] ?? u?['profileImage'] ?? u?['imageUrl'];
                  }
                  final initials = username.isNotEmpty ? username[0].toUpperCase() : '?';

                  return Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 3,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // USER HEADER
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: const Color(0xFF0D2236),
                                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                    ? CachedNetworkImageProvider(photoUrl)
                                    : null,
                                child: photoUrl == null || photoUrl.isEmpty
                                    ? Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                                    Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.white)),
                                  ],
                                ),
                              ),
                              if (isOwn)
                                PopupMenuButton(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  onSelected: (v) {
                                    if (v == 'edit') {}
                                    if (v == 'delete') {}
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // COMMENT TEXT
                          Text(data['comment'] ?? '', style: const TextStyle(fontSize: 14.5, height: 1.5)),
                          const SizedBox(height: 12),

                          // IMAGES
                          if (imageUrls.isNotEmpty)
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: imageUrls.length,
                                itemBuilder: (c, idx) => GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullScreenPhotoGallery(imageUrls: imageUrls, initialIndex: idx),
                                    ),
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    width: 120,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(
                                        image: CachedNetworkImageProvider(imageUrls[idx]),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (imageUrls.isNotEmpty) const SizedBox(height: 12),

                          // ACTIONS
                          Row(
                            children: [
                              // LIKE / DISLIKE – NOW FULLY SAFE
                              Expanded(
                                flex: 3,
                                child: StreamBuilder<DocumentSnapshot>(
                                  stream: firestore
                                      .collection('products')
                                      .doc(widget.productId)
                                      .collection('comments')
                                      .doc(commentId)
                                      .collection('reactions')
                                      .doc(_user?.uid)
                                      .snapshots(),
                                  builder: (c, snap) {
                                    final data = snap.data?.data() as Map<String, dynamic>?;
                                    final type = data?['type'] as String?;
                                    final isLiked = type == 'like';
                                    final isDisliked = type == 'dislike';
                          
                                    return FittedBox(  // This is the magic fix
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                                              color: isLiked ? Colors.blue : Colors.grey[600],
                                              size: 20,
                                            ),
                                            onPressed: _user == null ? null : () => _toggleReaction(commentId, true),
                                          ),
                                          Text('$likeCount', style: const TextStyle(fontSize: 13)),
                                          const SizedBox(width: 12),
                                          IconButton(
                                            icon: Icon(
                                              isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                                              color: isDisliked ? Colors.red : Colors.grey[600],
                                              size: 20,
                                            ),
                                            onPressed: _user == null ? null : () => _toggleReaction(commentId, false),
                                          ),
                                          Text('$dislikeCount', style: const TextStyle(fontSize: 13)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                          
                              // REPLY & REPORT – Always visible
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _showReplyDialog(commentId),
                                    icon: const Icon(Icons.reply, size: 18),
                                    label: const Text('Reply'),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      minimumSize: const Size(0, 36),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _showReportDialog(
                                      commentId: commentId,
                                      replyId: null,
                                      authorName: username,
                          ),
                                    icon: const Icon(Icons.flag_outlined, size: 16, color: Colors.red),
                                    label: const Text('Report', style: TextStyle(color: Colors.red, fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      minimumSize: const Size(0, 36),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // REPLIES SECTION
                          RepliesSection(
                            productId: widget.productId,
                            commentId: commentId,
                            onReply: (replyId) => _showReplyDialog(commentId, parentReplyId: replyId),
                            onReport: (commentId, replyId, authorName) => _showReportDialog(
                                commentId: commentId,
                                replyId: replyId,
                                authorName: authorName,
                              ),
                            mainCommentData: data,
                            username: username,
                            photoUrl: photoUrl,
                            dateStr: dateStr,
                            imageUrls: imageUrls,
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

// ── REPLIES SECTION – CLEAN & MODERN ─────────────────────
class RepliesSection extends StatelessWidget {
  final String productId;
  final String commentId;
  final Function(String?) onReply;
  final Function(String commentId, String? replyId, String authorName) onReport;
  final Map<String, dynamic> mainCommentData;
  final String username;
  final String? photoUrl;
  final String dateStr;
  final List<String> imageUrls;

  const RepliesSection({
    super.key,
    required this.productId,
    required this.commentId,
    required this.onReply,
    required this.onReport,
    required this.mainCommentData,
    required this.username,
    required this.photoUrl,
    required this.dateStr,
    required this.imageUrls,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('products')
          .doc(productId)
          .collection('comments')
          .doc(commentId)
          .collection('replies')
          .orderBy('timestamp')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final replies = snapshot.data!.docs;
        final visibleReplies = replies.length > 2 ? replies.take(2).toList() : replies;

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            children: [
              ...visibleReplies.map((doc) => ReplyWidget(
                    key: ValueKey(doc.id),
                    replyDoc: doc,
                    productId: productId,
                    parentCommentId: commentId,
                    parentReplyId: doc.id,
                    onReply: onReply,
                    onReport: onReport,
                    depth: 1,
                  )),

              if (replies.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 12, left: 56),
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullRepliesScreen(
                            productId: productId,
                            commentId: commentId,
                            mainCommentData: mainCommentData,
                            username: username,
                            photoUrl: photoUrl,
                            dateStr: dateStr,
                            imageUrls: imageUrls,
                            onReply: onReply,
                            onReport: onReport,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'View all ${replies.length} replies',
                      style: const TextStyle(
                        color: Colors.purple,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── REPLY WIDGET – WITH REPORT BUTTON ─────────────────────
class ReplyWidget extends StatelessWidget {
  final DocumentSnapshot replyDoc;
  final String productId;
  final String parentCommentId;
  final String parentReplyId;
  final Function(String?) onReply;
  final Function(String commentId, String? replyId, String authorName) onReport;
  final int depth;

  const ReplyWidget({
    super.key,
    required this.replyDoc,
    required this.productId,
    required this.parentCommentId,
    required this.parentReplyId,
    required this.onReply,
    required this.onReport,
    this.depth = 1,
  });

  @override
  Widget build(BuildContext context) {
    final rd = replyDoc.data() as Map<String, dynamic>;
    final replyId = replyDoc.id;
    final userId = rd['userId'] as String?;

    return FutureBuilder<DocumentSnapshot>(
      future: userId != null ? firestore.collection('users').doc(userId).get() : null,
      builder: (context, snap) {
        String name = rd['username'] ?? 'User';
        String? photoUrl;
        if (snap.hasData && snap.data!.exists) {
          final u = snap.data!.data() as Map<String, dynamic>?;
          name = u?['username'] ?? u?['fullName'] ?? name;
          photoUrl = u?['photoURL'] ?? u?['profileImage'];
        }

        final timestamp = (rd['timestamp'] as Timestamp?)?.toDate();
        final dateStr = timestamp != null
            ? DateFormat('MMM d').format(timestamp)
            : 'Just now';

        final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

        final indent = (depth - 1).clamp(0, 5) * 36.0 + 16.0;

        return Padding(
          padding: EdgeInsets.only(left: indent, top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (depth > 1)
                    Container(
                      width: 2,
                      height: 48,
                      color: Colors.grey.shade300,
                      margin: const EdgeInsets.only(right: 14),
                    ),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(photoUrl)
                        : null,
                    child: photoUrl == null || photoUrl.isEmpty
                        ? Text(initials, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 8),
                              Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.flag_outlined, size: 18, color: Colors.red),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => onReport(parentCommentId, replyId, name),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(rd['text'], style: const TextStyle(fontSize: 14.5, height: 1.4)),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () => onReply(replyId),
                            icon: const Icon(Icons.reply, size: 16),
                            label: const Text('Reply', style: TextStyle(fontSize: 13)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.purple,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Nested replies
              StreamBuilder<QuerySnapshot>(
                stream: firestore
                    .collection('products')
                    .doc(productId)
                    .collection('comments')
                    .doc(parentCommentId)
                    .collection('replies')
                    .doc(replyId)
                    .collection('replies')
                    .orderBy('timestamp')
                    .snapshots(),
                builder: (context, nestedSnapshot) {
                  if (!nestedSnapshot.hasData || nestedSnapshot.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: nestedSnapshot.data!.docs.map((doc) => ReplyWidget(
                        key: ValueKey(doc.id),
                        replyDoc: doc,
                        productId: productId,
                        parentCommentId: parentCommentId,
                        parentReplyId: replyId,
                        onReply: onReply,
                        onReport: onReport,
                        depth: depth + 1,
                      )).toList(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── FULL REPLIES SCREEN ─────────────────────
class FullRepliesScreen extends StatelessWidget {
  final Function(String?) onReply;
  final Function(String commentId, String? replyId, String authorName) onReport;
  final String productId;
  final String commentId;
  final Map<String, dynamic> mainCommentData;
  final String username;
  final String? photoUrl;
  final String dateStr;
  final List<String> imageUrls;

  const FullRepliesScreen({
    super.key,
    required this.onReply,
    required this.onReport,
    required this.productId,
    required this.commentId,
    required this.mainCommentData,
    required this.username,
    required this.photoUrl,
    required this.dateStr,
    required this.imageUrls,
  });

  @override
  Widget build(BuildContext context) {
    final parentState = context.findAncestorStateOfType<_AllCommentsScreenState>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2236),
        title: const Text('Comment Thread', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('products')
            .doc(productId)
            .collection('comments')
            .doc(commentId)
            .collection('replies')
            .orderBy('timestamp')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          final replies = snapshot.data!.docs;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // MAIN COMMENT
              Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF0D2236),
                            backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(photoUrl!)
                                : null,
                            child: photoUrl == null || photoUrl!.isEmpty
                                ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                                Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.white)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(mainCommentData['comment'] ?? '', style: const TextStyle(fontSize: 14.5, height: 1.5)),
                      if (imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: imageUrls.length,
                            itemBuilder: (c, i) => GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => FullScreenPhotoGallery(imageUrls: imageUrls, initialIndex: i)),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 120,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  image: DecorationImage(
                                    image: CachedNetworkImageProvider(imageUrls[i]),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => onReply(null),
                            icon: const Icon(Icons.reply, size: 18, color: Colors.purple),
                            label: const Text('Reply', style: TextStyle(color: Colors.purple)),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
  onPressed: () => onReport(commentId, null, username), // CLEAN & WORKING
  icon: const Icon(Icons.flag_outlined, size: 18, color: Colors.red),
  label: const Text('Report', style: TextStyle(color: Colors.red, fontSize: 13)),
),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Replies', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),

              if (replies.isEmpty)
                const Center(child: Text('No replies yet', style: TextStyle(color: Colors.white54)))
              else
                ...replies.map((doc) => ReplyWidget(
                      key: ValueKey(doc.id),
                      replyDoc: doc,
                      productId: productId,
                      parentCommentId: commentId,
                      parentReplyId: doc.id,
                      onReply: (id) => onReply(id),
                      onReport: onReport,
                      depth: 1,
                    )),
            ],
          );
        },
      ),
    );
  }
}

// ── FULL SCREEN GALLERY ─────────────────────────────────────
class FullScreenPhotoGallery extends StatelessWidget {
  final List<String> imageUrls;
  final int initialIndex;
  const FullScreenPhotoGallery({super.key, required this.imageUrls, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: PhotoViewGallery.builder(
        itemCount: imageUrls.length,
        builder: (c, i) => PhotoViewGalleryPageOptions(
          imageProvider: CachedNetworkImageProvider(imageUrls[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 2.5,
        ),
        pageController: PageController(initialPage: initialIndex),
      ),
    );
  }
}