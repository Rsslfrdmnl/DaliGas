// lib/screens/all_comments_screen.dart
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

class AllCommentsScreen extends StatefulWidget {
  final String productId;
  const AllCommentsScreen({super.key, required this.productId});

  @override
  State<AllCommentsScreen> createState() => _AllCommentsScreenState();
}

class _AllCommentsScreenState extends State<AllCommentsScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  final ImagePicker _picker = ImagePicker();

  // ── REACTION (LIKE / DISLIKE) ─────────────────────────────────────
  Future<void> _toggleReaction(String commentId, bool isLike) async {
  if (_user == null) return;
  final reactionRef = FirebaseFirestore.instance
      .collection('products')
      .doc(widget.productId)
      .collection('comments')
      .doc(commentId)
      .collection('reactions')
      .doc(_user!.uid);

  final commentRef = FirebaseFirestore.instance
      .collection('products')
      .doc(widget.productId)
      .collection('comments')
      .doc(commentId);

  await FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await reactionRef.get();
    final current = snap.data()?['type'] as String?;

    if (current == (isLike ? 'like' : 'dislike')) {
      // 🔸 Remove existing reaction
      tx.delete(reactionRef);
      tx.update(commentRef, {
        isLike ? 'likeCount' : 'dislikeCount': FieldValue.increment(-1),
      });
    } else {
      // 🔸 Add or switch reaction
      tx.set(
        reactionRef,
        {
          'type': isLike ? 'like' : 'dislike',
          'ts': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (current == null) {
        // New reaction
        tx.update(commentRef, {
          isLike ? 'likeCount' : 'dislikeCount': FieldValue.increment(1),
        });
      } else if (current == 'like' && !isLike) {
        // Switched from like → dislike
        tx.update(commentRef, {
          'likeCount': FieldValue.increment(-1),
          'dislikeCount': FieldValue.increment(1),
        });
      } else if (current == 'dislike' && isLike) {
        // Switched from dislike → like
        tx.update(commentRef, {
          'dislikeCount': FieldValue.increment(-1),
          'likeCount': FieldValue.increment(1),
        });
      }
    }
  });
}


  // ── REPORT COMMENT ───────────────────────────────────────────────
  Future<void> _reportComment(String commentId, String reason) async {
    if (_user == null) return;
    await FirebaseFirestore.instance.collection('reports').add({
      'type': 'comment',
      'productId': widget.productId,
      'commentId': commentId,
      'reporterId': _user!.uid,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Comment reported')));
  }

  // ── EDIT COMMENT ─────────────────────────────────────────────────
  Future<void> _editComment(String commentId, String currentText) async {
    final ctrl = TextEditingController(text: currentText);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(controller: ctrl, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .collection('comments')
          .doc(commentId)
          .update({'comment': result, 'edited': true});
    }
  }

  // ── DELETE COMMENT ───────────────────────────────────────────────
  Future<void> _deleteComment(String commentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .collection('comments')
          .doc(commentId)
          .delete();
    }
  }

  // ── REPLY TO COMMENT ─────────────────────────────────────────────
  Future<void> _reply(String parentId) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reply'),
        content: TextField(controller: ctrl, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();
      final username = userDoc['username'] ?? 'Anonymous';

      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .collection('comments')
          .doc(parentId)
          .collection('replies')
          .add({
        'userId': _user!.uid,
        'username': username,
        'text': result,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
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
        stream: FirebaseFirestore.instance
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
            return const Center(
                child: Text('No comments yet.', style: TextStyle(color: Colors.white70)));
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

              final dateStr = (data['timestamp'] as Timestamp?)
                      ?.toDate()
                      .let((d) => '${d.month}/${d.day}/${d.year}') ??
                  'Just now';

              final likeCount = (data['likeCount'] ?? 0) as int;
              final dislikeCount = (data['dislikeCount'] ?? 0) as int;
              final imageUrls = (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // USER + DATE + MENU
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data['username'] ?? 'Anonymous',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF0D2236)),
                            ),
                          ),
                          Text(dateStr,
                              style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          if (isOwn)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (v) {
                                if (v == 'edit') _editComment(commentId, data['comment']);
                                if (v == 'delete') _deleteComment(commentId);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // COMMENT TEXT
                      Text(data['comment'] ?? '',
                          style: const TextStyle(fontSize: 14, height: 1.4)),
                      const SizedBox(height: 12),

                      // IMAGES
                      if (imageUrls.isNotEmpty)
                        SizedBox(
                          height: 110,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: imageUrls.length,
                            itemBuilder: (c, idx) => GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenPhotoGallery(
                                    imageUrls: imageUrls,
                                    initialIndex: idx,
                                  ),
                                ),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                width: 110,
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

                      // ── REACTIONS + ACTIONS (NO OVERFLOW) ─────────────────────────────────────
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StreamBuilder<DocumentSnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('products')
                                    .doc(widget.productId)
                                    .collection('comments')
                                    .doc(commentId)
                                    .collection('reactions')
                                    .doc(_user?.uid)
                                    .snapshots(),
                                builder: (c, snap) {
                                  final type =
                                      (snap.data?.data() as Map<String, dynamic>?)?['type'];
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          type == 'like'
                                              ? Icons.thumb_up
                                              : Icons.thumb_up_outlined,
                                          color:
                                              type == 'like' ? Colors.blue : Colors.grey,
                                          size: 22,
                                        ),
                                        onPressed: _user == null
                                            ? null
                                            : () => _toggleReaction(commentId, true),
                                        constraints: const BoxConstraints(),
                                      ),
                                      Text('$likeCount',
                                          style: const TextStyle(fontSize: 13)),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: Icon(
                                          type == 'dislike'
                                              ? Icons.thumb_down
                                              : Icons.thumb_down_outlined,
                                          color:
                                              type == 'dislike' ? Colors.red : Colors.grey,
                                          size: 22,
                                        ),
                                        onPressed: _user == null
                                            ? null
                                            : () => _toggleReaction(commentId, false),
                                        constraints: const BoxConstraints(),
                                      ),
                                      Text('$dislikeCount',
                                          style: const TextStyle(fontSize: 13)),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () => _reply(commentId),
                            icon: const Icon(Icons.reply, size: 18),
                            label: const Text('Reply',
                                style: TextStyle(fontSize: 13)),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _reportComment(commentId, 'Inappropriate'),
                            icon:
                                const Icon(Icons.flag_outlined, size: 18),
                            label: const Text('Report',
                                style: TextStyle(fontSize: 13)),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),

                      // REPLIES
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('products')
                            .doc(widget.productId)
                            .collection('comments')
                            .doc(commentId)
                            .collection('replies')
                            .orderBy('timestamp')
                            .snapshots(),
                        builder: (c, replySnap) {
                          if (!replySnap.hasData ||
                              replySnap.data!.docs.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 12, left: 16),
                            child: Column(
                              children: replySnap.data!.docs.map((r) {
                                final rd = r.data() as Map<String, dynamic>;
                                final rDate = (rd['timestamp'] as Timestamp?)
                                        ?.toDate()
                                        .let((d) => '${d.month}/${d.day}') ??
                                    '';
                                return Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const CircleAvatar(
                                          radius: 12,
                                          child:
                                              Icon(Icons.person, size: 14)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                                color: Colors.black87),
                                            children: [
                                              TextSpan(
                                                text:
                                                    '${rd['username'] ?? 'Anon'} ',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              TextSpan(text: rd['text']),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Text(rDate,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey)),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── FULL SCREEN GALLERY ───────────────────────────────────────
class FullScreenPhotoGallery extends StatelessWidget {
  final List<String> imageUrls;
  final int initialIndex;
  const FullScreenPhotoGallery(
      {super.key, required this.imageUrls, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white)),
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

// Helper extension
extension on DateTime? {
  T let<T>(T Function(DateTime) block) =>
      this == null ? null as T : block(this!);
}
