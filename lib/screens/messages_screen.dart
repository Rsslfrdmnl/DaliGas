import 'dart:io';
import 'package:rxdart/rxdart.dart';
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
import 'package:daligas/main_mobile.dart';
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

  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    MessagesScreen.onChatUpdate = () => setState(() {});
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    MessagesScreen.onChatUpdate = null;
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: _backPressTimeout)) {
      _lastBackPress = now;
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.black87),
      );
      return false;
    }
    if (Platform.isAndroid) SystemNavigator.pop();
    return true;
  }

  // REAL-TIME + BATCHED EMPLOYEE NAMES
  Stream<List<Map<String, dynamic>>> _messagesStream() {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final ordersRef = firestore
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .where('deliveryStatus', isEqualTo: 'Shipped');

    return ordersRef.snapshots().switchMap((orderSnap) async* {
      if (orderSnap.docs.isEmpty) {
        yield [];
        return;
      }

      final employeeIds = <String>{};
      final orderMap = <String, String>{};

      for (final doc in orderSnap.docs) {
        final employeeId = doc['employeeId'] as String?;
        if (employeeId == null) continue;
        employeeIds.add(employeeId);
        orderMap[doc.id] = employeeId;
      }

      if (employeeIds.isEmpty) {
        yield [];
        return;
      }

      // BATCH FETCH EMPLOYEE NAMES
      final empSnaps = await firestore
          .collection('employees')
          .where(FieldPath.documentId, whereIn: employeeIds.toList())
          .get();

      final empNameMap = <String, String>{
        for (var doc in empSnaps.docs) doc.id: (doc['name'] ?? 'Driver').toLowerCase()
      };

      final List<Stream<Map<String, dynamic>>> chatStreams = [];

      for (final orderDoc in orderSnap.docs) {
        final orderId = orderDoc.id;
        final employeeId = orderDoc['employeeId'] as String?;
        if (employeeId == null) continue;

        final chatId = '${userId}_${employeeId}_$orderId';
        final driverName = empNameMap[employeeId] ?? 'driver';

        final chatStream = Rx.combineLatest3<
            DocumentSnapshot<Map<String, dynamic>>,
            DocumentSnapshot<Map<String, dynamic>>,
            QuerySnapshot<Map<String, dynamic>>,
            Map<String, dynamic>>(
          firestore.collection('chats').doc(chatId).snapshots(),
          firestore
              .collection('chats')
              .doc(chatId)
              .collection('metadata')
              .doc('info')
              .snapshots(),
          firestore
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(1)
              .snapshots(),
          (chatDoc, metaDoc, msgSnap) {
            if (!chatDoc.exists || chatDoc.data()?['deletedByCustomer'] == true) {
              return <String, dynamic>{};
            }

            bool isPinned = metaDoc.data()?['pinned'] == true;
            String lastMessage = 'No messages yet';
            Timestamp lastTimestamp = Timestamp.now();
            String? senderId;
            bool seen = true;

            if (msgSnap.docs.isNotEmpty) {
              final msg = msgSnap.docs.first.data();
              lastMessage = msg['text'] ?? 'No text';
              lastTimestamp = msg['timestamp'] ?? Timestamp.now();
              senderId = msg['senderId'];
              seen = msg['seen'] == true;

              if (senderId == userId) {
                lastMessage = 'You: $lastMessage';
              }
            }

            final isUnread = senderId == employeeId && !seen;

            return <String, dynamic>{
              'orderId': orderId,
              'employeeId': employeeId,
              'chatId': chatId,
              'isPinned': isPinned,
              'isUnread': isUnread,
              'lastMessage': lastMessage,
              'lastTimestamp': lastTimestamp,
              'title': driverName, // lowercase for search
            };
          },
        ).map((data) {
          if (data.isEmpty) return data;
          return <String, dynamic>{
            'title': empNameMap[data['employeeId']] ?? 'Driver', // original case
            'body': data['lastMessage'],
            'timeAgo': _formatTimestamp(data['lastTimestamp']),
            'orderId': data['orderId'],
            'employeeId': data['employeeId'],
            'chatId': data['chatId'],
            'isUnread': data['isUnread'],
            'isPinned': data['isPinned'],
            'timestamp': data['lastTimestamp'],
          };
        });

        chatStreams.add(chatStream);
      }

      if (chatStreams.isEmpty) {
        yield [];
        return;
      }

      yield* Rx.combineLatestList(chatStreams).map((list) {
        final chats = list.where((e) => e.isNotEmpty).toList();

        // SEARCH: only by driver name
        if (_searchQuery.isNotEmpty) {
          chats.removeWhere((chat) {
            final name = (chat['title'] as String).toLowerCase();
            return !name.contains(_searchQuery);
          });
        }

        chats.sort((a, b) {
          final aPinned = a['isPinned'] as bool? ?? false;
          final bPinned = b['isPinned'] as bool? ?? false;
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          return (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp);
        });

        return chats;
      });
    });
  }

  Stream<int> _unreadCountStream() {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    return firestore
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .where('deliveryStatus', isEqualTo: 'Shipped')
        .snapshots()
        .switchMap((orderSnap) {
      final streams = <Stream<int>>[];
      for (var doc in orderSnap.docs) {
        final employeeId = doc['employeeId'] as String?;
        if (employeeId == null) continue;
        final chatId = '${userId}_$employeeId}_${doc.id}';

        final s = firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .where('senderId', isNotEqualTo: userId)
            .where('seen', isEqualTo: false)
            .snapshots()
            .map((snap) => snap.docs.length);

        streams.add(s);
      }
      return streams.isEmpty
          ? Stream.value(0)
          : Rx.combineLatestList(streams).map((list) => list.fold(0, (a, b) => a + b));
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
            Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        ),
      );

  Future<void> _deleteChat(String chatId) async {
    await firestore
        .collection('chats')
        .doc(chatId)
        .set({'deletedByCustomer': true}, SetOptions(merge: true));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat deleted')));
  }

  Future<void> _togglePinChat(String chatId, bool currentStatus) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final userRef = firestore.collection('users').doc(userId);

    try {
      await firestore.runTransaction((transaction) async {
        final userSnap = await transaction.get(userRef);
        int pinnedCount = userSnap.data()?['pinnedChatsCount'] ?? 0;

        final metaRef = firestore
            .collection('chats')
            .doc(chatId)
            .collection('metadata')
            .doc('info');

        if (currentStatus) {
          transaction.set(metaRef, {'pinned': false}, SetOptions(merge: true));
          transaction.set(userRef, {'pinnedChatsCount': FieldValue.increment(-1)}, SetOptions(merge: true));
        } else {
          if (pinnedCount >= _maxPinnedChats) throw Exception('Max 3');
          transaction.set(metaRef, {'pinned': true}, SetOptions(merge: true));
          transaction.set(userRef, {'pinnedChatsCount': FieldValue.increment(1)}, SetOptions(merge: true));
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString().contains('Max') ? 'Max 3 chats can be pinned' : 'Error'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleReadStatus(String chatId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final latest = await firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('timestamp', isNotEqualTo: null)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (latest.docs.isEmpty) return;
    final data = latest.docs.first.data() as Map<String, dynamic>;
    final senderId = data['senderId'] as String?;
    if (senderId == uid) return;
    await latest.docs.first.reference.update({'seen': !(data['seen'] == true)});
  }

  Future<void> _markAsRead(String chatId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final unread = await firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('seen', isEqualTo: false)
        .where('senderId', isNotEqualTo: uid)
        .get();
    for (var doc in unread.docs) {
      await doc.reference.update({'seen': true});
    }
  }

  Future<void> _markAllAsRead() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final orders = await firestore
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .where('deliveryStatus', isEqualTo: 'Shipped')
        .get();

    for (var order in orders.docs) {
      final employeeId = order['employeeId'] as String?;
      if (employeeId == null) continue;
      final chatId = '${userId}_$employeeId}_${order.id}';
      await _markAsRead(chatId);
    }
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
          title: _isSearching
              ? Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search drivers...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                )
              : const Text('Messages', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          actions: [
            // SEARCH ICON
            InkWell(
              onTap: () => setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              }),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
              ),
            ),
            const SizedBox(width: 16),

            // CART ICON (aligned with HomeScreen)
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const cart.CartScreen())),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.shopping_bag_outlined, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: Colors.white.withOpacity(0.3)),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            setState(() {});
            await Future.delayed(const Duration(milliseconds: 500));
          },
          color: Colors.cyan,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _messagesStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: 3,
                  itemBuilder: (_, __) => const _SkeletonCard(),
                );
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _empty(_searchQuery.isEmpty ? 'No active chats' : 'No drivers found');
              }
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final msg = snapshot.data![index];
                  final chatId = msg['chatId'] as String;
                  final isPinned = msg['isPinned'] as bool? ?? false;

                  return Dismissible(
                    key: Key(chatId),
                    direction: DismissDirection.horizontal,
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.endToStart) {
                        await _deleteChat(chatId);
                        return true;
                      } else if (direction == DismissDirection.startToEnd) {
                        await _togglePinChat(chatId, isPinned);
                        return false;
                      }
                      return false;
                    },
                    background: Container(
                      color: Colors.green,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 20),
                      child: const Icon(Icons.push_pin, color: Colors.white),
                    ),
                    secondaryBackground: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    child: MessageCard(
                      msg: msg,
                      onDelete: _deleteChat,
                      onPin: _togglePinChat,
                      onToggleRead: _toggleReadStatus,
                      onMarkRead: _markAsRead,
                    ),
                  );
                },
              );
            },
          ),
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
          child: StreamBuilder<int>(
            stream: _unreadCountStream(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              return BottomNavigationBar(
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
                    case 1: break;
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
                items: [
                  const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home, color: Color(0xFF0D2236)), label: ''),
                  BottomNavigationBarItem(
                    icon: Badge(
                      label: Text('$unreadCount', style: const TextStyle(fontSize: 10)),
                      isLabelVisible: unreadCount > 0,
                      backgroundColor: Colors.red,
                      child: const Icon(Icons.chat_bubble_outline),
                    ),
                    activeIcon: Badge(
                      label: Text('$unreadCount', style: const TextStyle(fontSize: 10)),
                      isLabelVisible: unreadCount > 0,
                      backgroundColor: Colors.red,
                      child: const Icon(Icons.chat_bubble, color: Color(0xFF0D2236)),
                    ),
                    label: '',
                  ),
                  const BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), activeIcon: Icon(Icons.shopping_bag, color: Color(0xFF0D2236)), label: ''),
                  const BottomNavigationBarItem(icon: Icon(Icons.help_outline), activeIcon: Icon(Icons.help, color: Color(0xFF0D2236)), label: ''),
                  const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person, color: Color(0xFF0D2236)), label: ''),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── SKELETON CARD ──
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A3A5F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const CircleAvatar(radius: 26, backgroundColor: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 120, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Container(height: 14, width: double.infinity, color: Colors.grey[400]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── MESSAGE CARD ──
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

    return Semantics(
      label: '${widget.msg['title']}, Order #${_shortOrderId(widget.msg['orderId'])}, ${isUnread ? 'unread' : 'read'}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => isPressed = true),
        onTapUp: (_) => setState(() => isPressed = false),
        onTapCancel: () => setState(() => isPressed = false),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showBottomSheet(context, chatId, isUnread, isPinned);
        },
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
                            future: firestore.collection('employees').doc(employeeId).get(),
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