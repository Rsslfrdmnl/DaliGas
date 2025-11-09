import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/screens/account_screen.dart';
import 'package:daligas/screens/cart_screen.dart' as cart;
import 'package:daligas/screens/chat_screen.dart';
import 'package:daligas/screens/help_screen.dart';
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/purchases_screen.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  static VoidCallback? onChatUpdate;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

String _shortOrderId(String fullId) => fullId.length <= 5 ? fullId : fullId.substring(fullId.length - 5);

class _MessagesScreenState extends State<MessagesScreen> {
  DateTime? _lastBackPress;
  static const int _backPressTimeout = 2;
  static const int _maxPinnedChats = 3;

  @override
  void initState() {
    super.initState();
    MessagesScreen.onChatUpdate = () => setState(() {});
  }

  @override
  void dispose() {
    MessagesScreen.onChatUpdate = null;
    super.dispose();
  }

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
      exit(0);
    }
    return true;
  }

  // ── STREAM: Pinned first, then by timestamp ──
  Stream<List<Map<String, dynamic>>> _messagesStream() {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .where('deliveryStatus', isEqualTo: 'Shipped')
        .snapshots()
        .asyncExpand((orderSnapshot) async* {
      final List<Map<String, dynamic>> chats = [];

      for (final orderDoc in orderSnapshot.docs) {
        final data = orderDoc.data();
        final employeeId = data['employeeId'] as String?;
        if (employeeId == null) continue;

        final chatId = '${userId}_${employeeId}_${orderDoc.id}';

        final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(chatId).get();
        if (!chatDoc.exists || chatDoc.data()?['deletedByCustomer'] == true) continue;

        final empDoc = await FirebaseFirestore.instance.collection('employees').doc(employeeId).get();
        final driverName = empDoc.exists ? empDoc['name'] ?? 'Driver' : 'Driver';

        final msgSnap = await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

        if (msgSnap.docs.isEmpty) continue;

        final msg = msgSnap.docs.first.data();
        final lastMessage = msg['text'] ?? 'No text';
        final timestamp = msg['timestamp'] as Timestamp?;
        final senderId = msg['senderId'] as String?;
        final seen = msg['seen'] == true;

        final timeAgo = timestamp != null ? _formatTimestamp(timestamp) : '';
        final isUnread = senderId == employeeId && !seen;

        final metaDoc = await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('metadata')
            .doc('info')
            .get();
        final isPinned = metaDoc.exists && metaDoc['pinned'] == true;

        chats.add({
          'title': driverName,
          'body': lastMessage,
          'timeAgo': timeAgo,
          'orderId': orderDoc.id,
          'employeeId': employeeId,
          'chatId': chatId,
          'isUnread': isUnread,
          'isPinned': isPinned,
          'timestamp': timestamp ?? Timestamp.now(),
        });
      }

      // Sort: Pinned first → then newest message
      chats.sort((a, b) {
        final aPinned = a['isPinned'] as bool? ?? false;
        final bPinned = b['isPinned'] as bool? ?? false;

        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;

        final aTs = a['timestamp'] as Timestamp;
        final bTs = b['timestamp'] as Timestamp;
        return bTs.compareTo(aTs);
      });

      yield chats;
    });
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }

  Widget _empty(String msg) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 60, color: Colors.white54),
            const SizedBox(height: 16),
            Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
          ],
        ),
      );

  Future<void> _deleteChat(String chatId) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({'deletedByCustomer': true}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat deleted')));
      }
    } catch (e) {
      if (kDebugMode) print('Delete error: $e');
    }
  }

  // ── FIXED PIN FUNCTION WITH MAX 3 LIMIT ──
  Future<void> _togglePinChat(String chatId, bool currentStatus) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final userSnap = await transaction.get(userRef);
        int pinnedCount = 0;
        if (userSnap.exists) {
          pinnedCount = userSnap.data()?['pinnedChatsCount'] ?? 0;
        }

        final metaRef = FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('metadata')
            .doc('info');

        if (currentStatus) {
          // Unpinning
          transaction.set(metaRef, {'pinned': false}, SetOptions(merge: true));
          transaction.set(userRef, {'pinnedChatsCount': FieldValue.increment(-1)}, SetOptions(merge: true));
        } else {
          // Pinning
          if (pinnedCount >= _maxPinnedChats) {
            throw Exception('Maximum 3 chats can be pinned');
          }
          transaction.set(metaRef, {'pinned': true}, SetOptions(merge: true));
          transaction.set(userRef, {'pinnedChatsCount': FieldValue.increment(1)}, SetOptions(merge: true));
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString() == 'Exception: Maximum 3 chats can be pinned'
                ? 'You can only pin up to 3 chats.'
                : 'Error updating pin status'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (mounted) setState(() {});
  }

  Future<void> _toggleReadStatus(String chatId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final latest = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (latest.docs.isEmpty) return;

    final data = latest.docs.first.data();
    final senderId = data['senderId'] as String?;
    if (senderId == uid) return;

    await latest.docs.first.reference.update({'seen': !(data['seen'] == true)});
    if (mounted) setState(() {});
  }

  Future<void> _markAsRead(String chatId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final unread = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('seen', isEqualTo: false)
        .where('senderId', isNotEqualTo: uid)
        .get();

    for (var doc in unread.docs) {
      await doc.reference.update({'seen': true});
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D2236),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D2236),
          elevation: 0,
          titleSpacing: -8,
          automaticallyImplyLeading: false,
          leading: const SizedBox.shrink(),
          title: const Text('Messages', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const cart.CartScreen())),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Colors.white)),
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _messagesStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _empty('No messages found!');
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) => MessageCard(
                msg: snapshot.data![index],
                onDelete: _deleteChat,
                onPin: _togglePinChat,
                onToggleRead: _toggleReadStatus,
                onMarkRead: _markAsRead,
              ),
            );
          },
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            currentIndex: 1,
            selectedItemColor: const Color(0xFF0D2236),
            unselectedItemColor: Colors.black,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            onTap: (index) {
              switch (index) {
                case 0:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const HomeScreen(), transitionDuration: Duration.zero));
                  break;
                case 1:
                  break;
                case 2:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const PurchasesScreen(currentIndex: 2), transitionDuration: Duration.zero));
                  break;
                case 3:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const HelpScreen(currentIndex: 3), transitionDuration: Duration.zero));
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
}

// ── MESSAGE CARD (unchanged except better pin icon) ──
class MessageCard extends StatefulWidget {
  final Map<String, dynamic> msg;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String, bool) onPin;
  final Future<void> Function(String) onToggleRead;
  final Future<void> Function(String) onMarkRead;

  const MessageCard({
    super.key,
    required this.msg,
    required this.onDelete,
    required this.onPin,
    required this.onToggleRead,
    required this.onMarkRead,
  });

  @override
  State<MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<MessageCard> {
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    final chatId = widget.msg['chatId'] as String;
    final employeeId = widget.msg['employeeId'] as String;
    final isUnread = (widget.msg['isUnread'] as bool?) ?? false;
    final isPinned = (widget.msg['isPinned'] as bool?) ?? false;

    return GestureDetector(
      onTapDown: (_) => setState(() => isPressed = true),
      onTapUp: (_) => setState(() => isPressed = false),
      onTapCancel: () => setState(() => isPressed = false),
      onLongPress: () => _showBottomSheet(context, chatId, isUnread, isPinned),
      onTap: () {
        widget.onMarkRead(chatId);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              title: '${widget.msg['title']} • Order #${_shortOrderId(widget.msg['orderId'])}',
              chatId: chatId,
              isEmployee: false,
              orderId: widget.msg['orderId'],
            ),
          ),
        ).then((_) => widget.onMarkRead(chatId));
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: isPressed ? 0.6 : 1.0,
        child: Card(
          color: isUnread ? const Color(0xFF1A3A5F) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('employees').doc(employeeId).get(),
                          builder: (context, snapshot) {
                            String? imageUrl = snapshot.hasData && snapshot.data!.exists
                                ? snapshot.data!['profileImage'] as String?
                                : null;
                            return CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.grey,
                              backgroundImage: imageUrl?.isNotEmpty == true ? NetworkImage(imageUrl!) : null,
                              child: imageUrl?.isNotEmpty != true ? const Icon(Icons.person, color: Colors.white, size: 30) : null,
                            );
                          },
                        ),
                        if (isUnread)
                          const Positioned(right: 0, top: 0, child: CircleAvatar(radius: 6, backgroundColor: Colors.cyan)),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.msg['title'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isUnread ? 17 : 16,
                                    color: isUnread ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                widget.msg['timeAgo'] ?? '',
                                style: TextStyle(fontSize: 12, color: isUnread ? Colors.white70 : Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.msg['body'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: isUnread
                                  ? Colors.cyanAccent
                                  : (widget.msg['body'] == 'No messages yet' ? Colors.grey : Colors.black87),
                              fontStyle: widget.msg['body'] == 'No messages yet' ? FontStyle.italic : null,
                              fontWeight: isUnread ? FontWeight.w600 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Better positioned pin icon
              if (isPinned)
                const Positioned(
                  left: 8,
                  top: 8,
                  child: Icon(Icons.push_pin, size: 20, color: Colors.redAccent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBottomSheet(BuildContext context, String chatId, bool isUnread, bool isPinned) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.mark_chat_unread_outlined),
              title: Text(isUnread ? 'Mark as read' : 'Mark as unread'),
              onTap: () {
                Navigator.pop(context);
                widget.onToggleRead(chatId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(isPinned ? 'Unpin chat' : 'Pin to top'),
              onTap: () {
                Navigator.pop(context);
                widget.onPin(chatId, isPinned);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete chat'),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete Chat'),
                    content: const Text('Are you sure? This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(_, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) await widget.onDelete(chatId);
              },
            ),
          ],
        ),
      ),
    );
  }
}