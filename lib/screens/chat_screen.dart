// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:daligas/screens/messages_screen.dart';
import 'package:daligas/main_mobile.dart';

class ChatScreen extends StatefulWidget {
  final String title;
  final String chatId;
  final bool isEmployee;
  final String? orderId;

  const ChatScreen({
    super.key,
    required this.title,
    required this.chatId,
    required this.isEmployee,
    this.orderId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final userId = FirebaseAuth.instance.currentUser!.uid;

  late final CollectionReference _messagesRef;
  bool _isTyping = false;

  // Profile info
  String? _otherUserName;
  String? _otherUserPhoto;
  bool _isLoadingProfile = true;

@override
void initState() {
  super.initState();
  _messagesRef = firestore
      .collection('chats')
      .doc(widget.chatId)
      .collection('messages');

  _controller.addListener(() {
    final isTyping = _controller.text.isNotEmpty;
    if (isTyping != _isTyping) setState(() => _isTyping = isTyping);
  });

  _fetchOtherUserProfile();

  // ── REAL-TIME: Notify MessagesScreen on new message ──
  _messagesRef
      .orderBy('timestamp', descending: true)
      .limit(1)
      .snapshots()
      .listen((snapshot) {
    if (snapshot.docs.isNotEmpty && mounted) {
      MessagesScreen.onChatUpdate?.call();
    }
  });
}

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── FETCH OTHER USER PROFILE ─────────────────────────────────────────────
  Future<void> _fetchOtherUserProfile() async {
    setState(() => _isLoadingProfile = true);

    try {
      final parts = widget.chatId.split('_');
      if (parts.length < 3) {
        setState(() => _isLoadingProfile = false);
        return;
      }

      final customerId = parts[0];
      final employeeId = parts[1];
      // parts[2] = orderId

      String targetId;
      String collection;
      String nameField;

      if (widget.isEmployee) {
        // Employee → show customer
        targetId = customerId;
        collection = 'users';
        nameField = 'username';
      } else {
        // Customer → show employee
        targetId = employeeId;
        collection = 'employees';
        nameField = 'name';
      }

      final doc = await firestore
          .collection(collection)
          .doc(targetId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _otherUserName = data[nameField] ?? 'User';
          _otherUserPhoto = data['profileImage'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  // ── SEND MESSAGE (WITH CHAT CREATION) ───────────────────────────────────
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final chatRef = firestore.collection('chats').doc(widget.chatId);

    // CREATE CHAT DOCUMENT IF NOT EXISTS
    final chatDoc = await chatRef.get();
    if (!chatDoc.exists) {
      final parts = widget.chatId.split('_');
      await chatRef.set({
        'customerId': parts[0],
        'employeeId': parts[1],
        'orderId': parts[2],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // SEND MESSAGE
    await chatRef.collection('messages').add({
      'text': text,
      'senderId': userId,
      'senderRole': widget.isEmployee ? 'employee' : 'customer',
      'timestamp': FieldValue.serverTimestamp(),
      'seen': false,
    });

    _scrollToBottom();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position.maxScrollExtent + 100;
    if (animate) {
      _scrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(position);
    }
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    return DateFormat('h:mm a').format(timestamp.toDate());
  }

  // ── 3-DOT MENU ───────────────────────────────────────────────────────────
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Chat Options',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),

            // 1. Clear Chat
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Clear Chat'),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Clear Chat?'),
                    content: const Text('This only clears your view.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final batch = firestore.batch();
                  final snapshot = await _messagesRef.get();
                  for (var doc in snapshot.docs) {
                    if ((doc['senderId'] == userId) || widget.isEmployee) {
                      batch.delete(doc.reference);
                    }
                  }
                  await batch.commit();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat cleared')),
                  );
                }
              },
            ),

            // 2. Copy Chat ID
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blue),
              title: const Text('Copy Chat ID'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.chatId));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat ID copied')),
                );
              },
            ),

            // REPORT DRIVER – FINAL PROFESSIONAL VERSION
            if (!widget.isEmployee)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.red),
                title: const Text('Report Driver'),
                onTap: () async {
                  Navigator.pop(context);
                  _showReportDialog();
                },
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showReportDialog() async {
    final List<String> reportTypes = ['Comment', 'Reply', 'Chat', 'Review', 'Bug', 'Order Issue', 'Payment Problem', 'Delivery', 'Others'];
    final List<String> reasons = [
      "Rude or unprofessional behavior",
      "Did not follow delivery instructions",
      "Late delivery without communication",
      "Item damaged or missing",
      "Safety concern (reckless driving)",
      "Requested extra payment",
      "Wrong address or refused to deliver",
      "Spam or inappropriate content",
      "Other issue",
    ];

    String? selectedType;
    String? selectedReason;
    final detailsController = TextEditingController();

    // Scroll controllers for smooth auto-scroll
    final scrollController = ScrollController();
    final typeKey = GlobalKey();
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
              Text('Report Issue', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.7, // nice height
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What are you reporting?', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),

                  // Report Type
                  DropdownButtonFormField<String>(
                    key: typeKey,
                    value: selectedType,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    hint: const Text('Select report type'),
                    items: reportTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) {
                      setStateDialog(() {
                        selectedType = val;
                      });
                      // Auto-scroll to Reason after selecting type
                      Future.delayed(const Duration(milliseconds: 300), () {
                        Scrollable.ensureVisible(
                          reasonKey.currentContext!,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          alignment: 0.1,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Reason Section
                  const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(key: reasonKey), // Anchor point

                  ...reasons.map((r) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: selectedReason == r ? Colors.red.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedReason == r ? Colors.red.shade400 : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: RadioListTile<String>(
                          dense: true,
                          title: Text(r, style: const TextStyle(fontSize: 15)),
                          value: r,
                          groupValue: selectedReason,
                          activeColor: Colors.red.shade600,
                          onChanged: (val) {
                            setStateDialog(() {
                              selectedReason = val;
                            });
                            // Auto-scroll to Description after selecting reason
                            Future.delayed(const Duration(milliseconds: 300), () {
                              Scrollable.ensureVisible(
                                descriptionKey.currentContext!,
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeInOut,
                                alignment: 0.0,
                              );
                              // Optional: auto-focus the text field
                              FocusScope.of(context).requestFocus(FocusNode());
                            });
                          },
                        ),
                      )),

                  const SizedBox(height: 20),

                  // Description
                  const Text('Description (optional but recommended)', 
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(key: descriptionKey), // Anchor point
                  TextField(
                    controller: detailsController,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Provide more details about the issue...',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report cancelled')));
      return;
    }

    final type = result['type']!;
    final reason = result['reason']!;
    final details = result['details']!;
    final content = details.isNotEmpty ? '$reason\n\n$details' : reason;

    // === 1. Get reporter full name ===
    String reporterName = 'Unknown User';
    try {
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        reporterName = userDoc['fullName'] ?? userDoc['username'] ?? 'Customer';
      }
    } catch (e) {
      debugPrint('Failed to fetch reporter name: $e');
    }

    // === 2. Generate next REP-XXX ID ===
    String reportId = 'REP-001';
    final counterSnap = await firestore.collection('counters').doc('reports').get();
    int nextNum = 1;

    if (counterSnap.exists) {
      nextNum = (counterSnap['lastNumber'] ?? 0) + 1;
    }
    await firestore.collection('counters').doc('reports').set({'lastNumber': nextNum}, SetOptions(merge: true));
    reportId = 'REP-${nextNum.toString().padLeft(3, '0')}';

    // === 3. Format date ===
    final now = DateTime.now();
    final formattedDate = DateFormat('MMMM d, yyyy').format(now); // November 26, 2025

    // === 4. Extract employee info ===
    final parts = widget.chatId.split('_');
    final employeeId = parts.length > 1 ? parts[1] : null;
    final employeeName = widget.title;

    // === 5. Save report with EXACT admin format ===
    await firestore.collection('reports').doc(reportId).set({
      'reportId': reportId,
      'type': type,
      'reporterId': userId,
      'reporterName': reporterName,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'orderId': widget.orderId ?? '',
      'chatId': widget.chatId,
      'reason': reason,
      'content': content,
      'date': formattedDate,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending',
    });

    ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    backgroundColor: Colors.green.shade700,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    content: Row(
  children: [
    const Icon(Icons.check_circle, color: Colors.white),
    const SizedBox(width: 12),
    Expanded(
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 15, color: Colors.white),
          children: [
            const TextSpan(text: 'Report '),
            const TextSpan(text: 'submitted successfully!'),
          ],
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    ),
  ],
),
    duration: const Duration(seconds: 5),
  ),
);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E5E5),
      appBar: AppBar(
        backgroundColor: null,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[300],
              backgroundImage: _otherUserPhoto != null &&
                      _otherUserPhoto!.isNotEmpty
                  ? NetworkImage(_otherUserPhoto!)
                  : null,
              child: (_isLoadingProfile ||
                      _otherUserPhoto == null ||
                      _otherUserPhoto!.isEmpty)
                  ? const Icon(Icons.person, size: 18, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isLoadingProfile ? 'Loading...' : _otherUserName ?? widget.title,
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMoreOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: RefreshIndicator(
                onRefresh: () async => _scrollToBottom(animate: false),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _messagesRef.orderBy('timestamp').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No messages yet. Say hello!',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _scrollToBottom());

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final data = docs[i].data() as Map<String, dynamic>;
                        final docRef = docs[i].reference;
                        final isMe = data['senderId'] == userId;
                        final text = data['text'] ?? '';
                        final timestamp = data['timestamp'] as Timestamp?;
                        final seen = data['seen'] == true;

                        if (!isMe) {
                          docRef.set({'seen': true}, SetOptions(merge: true));
                        }

                        return GestureDetector(
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied')),
                            );
                          },
                          child: Align(
                            alignment:
                                isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? const Color(0xFF0D2236)
                                    : null,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    text,
                                    style: TextStyle(
                                      color:
                                          isMe ? Colors.white : Colors.black87,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatTime(timestamp),
                                        style: TextStyle(
                                          color: isMe
                                              ? Colors.white70
                                              : Colors.grey,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          seen ? Icons.done_all : Icons.done,
                                          size: 14,
                                          color:
                                              seen ? Colors.cyan : Colors.white70,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),

          // Typing indicator
          if (_isTyping)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  'Typing...',
                  style: TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                ),
              ),
            ),

          // Input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D2236),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}