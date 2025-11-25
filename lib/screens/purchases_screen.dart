import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import 'package:daligas/screens/account_screen.dart';
import 'package:daligas/screens/cart_screen.dart' as cart;
import 'package:daligas/screens/help_screen.dart';
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/messages_screen.dart';
import 'package:daligas/screens/review_order_screen.dart';
import 'package:daligas/screens/order_details_screen.dart';
import 'package:daligas/main_mobile.dart';

class PurchasesScreen extends StatefulWidget {
  final int currentIndex;
  const PurchasesScreen({super.key, this.currentIndex = 2});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final User? user = FirebaseAuth.instance.currentUser;

  // Reactive order counts for each tab
  final BehaviorSubject<Map<String, int>> _tabCounts = BehaviorSubject.seeded({
    'All': 0,
    'Processing': 0,
    'Shipped': 0,
    'Delivered': 0,
    'Review': 0,
  });

  // ADD: Track the Firestore subscription
  StreamSubscription<QuerySnapshot>? _ordersSubscription;

  DateTime? _lastBackPress;
  static const int _backPressTimeout = 2;

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

  @override
  void initState() {
    super.initState();
    if (user != null) {
      _listenToOrders();
    }
  }

  // FIXED: Safe listener with cancel + closed check
  void _listenToOrders() {
    // Cancel any previous subscription first
    _ordersSubscription?.cancel();

    _ordersSubscription = firestore
        .collection('orders')
        .where('userId', isEqualTo: user!.uid)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final docs = snapshot.docs;
      final counts = {
        'All': docs.length,
        'Processing': 0,
        'Shipped': 0,
        'Delivered': 0,
        'Review': 0,
      };

      for (final doc in docs) {
        final data = doc.data();
        final status = data['deliveryStatus'] ?? 'Processing';
        final reviewed = data['reviewed'] == true;

        counts[status] = (counts[status] ?? 0) + 1;
        if (status == 'Delivered' && !reviewed) {
          counts['Review'] = (counts['Review'] ?? 0) + 1;
        }
      }

      // Only add if subject is not closed
      if (!_tabCounts.isClosed) {
        _tabCounts.add(counts);
      }
    }, onError: (error) {
      debugPrint('Orders stream error: $error');
    });
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();  // Cancel Firestore listener
    _tabCounts.close();              // Close BehaviorSubject
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF052238),
        body: Center(child: Text('Please log in', style: TextStyle(color: Colors.white))),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: DefaultTabController(
        length: 5,
        child: Scaffold(
          backgroundColor: const Color(0xFF052238),
          appBar: AppBar(
            backgroundColor: const Color(0xFF052238),
            elevation: 0,
            titleSpacing: -8,
            automaticallyImplyLeading: false,
            leading: const SizedBox.shrink(),
            title: const Text('My Purchases', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            actions: [
              IconButton(
                icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const cart.CartScreen())),
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: StreamBuilder<Map<String, int>>(
                stream: _tabCounts.stream,
                builder: (context, snapshot) {
                  final counts = snapshot.data ?? {};
                  return TabBar(
                    isScrollable: false,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
                    tabs: [
                      _buildTab('All', counts['All']),
                      _buildTab('Processing', counts['Processing']),
                      _buildTab('Shipped', counts['Shipped']),
                      _buildTab('Delivered', counts['Delivered']),
                      _buildTab('Review', counts['Review']),
                    ],
                  );
                },
              ),
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              HapticFeedback.lightImpact();
              await Future.delayed(const Duration(milliseconds: 800));
            },
            color: Colors.cyan,
            child: TabBarView(
              children: [
                PurchasesTab(userId: user!.uid, statusFilter: null, tabCounts: _tabCounts),
                PurchasesTab(userId: user!.uid, statusFilter: 'Processing', tabCounts: _tabCounts),
                PurchasesTab(userId: user!.uid, statusFilter: 'Shipped', tabCounts: _tabCounts),
                PurchasesTab(userId: user!.uid, statusFilter: 'Delivered', tabCounts: _tabCounts),
                PurchasesTab(userId: user!.uid, statusFilter: 'Delivered', showReview: true, tabCounts: _tabCounts),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomNav(),
        ),
      ),
    );
  }

  Widget _buildTab(String label, int? count) {
    return Tab(
      child: FittedBox(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count != null && count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Theme(
      data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        currentIndex: widget.currentIndex,
        selectedItemColor: const Color(0xFF0D2236),
        unselectedItemColor: Colors.black,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        onTap: (index) {
          if (index == widget.currentIndex) return;
          switch (index) {
            case 0:
              Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const HomeScreen(), transitionDuration: Duration.zero));
              break;
            case 1:
              Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const MessagesScreen(), transitionDuration: Duration.zero));
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
    );
  }
}

class PurchasesTab extends StatelessWidget {
  final String userId;
  final String? statusFilter;
  final bool showReview;
  final BehaviorSubject<Map<String, int>> tabCounts;

  const PurchasesTab({
    super.key,
    required this.userId,
    this.statusFilter,
    this.showReview = false,
    required this.tabCounts,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('orders')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('No orders yet');
        }

        var orders = snapshot.data!.docs;

        if (statusFilter != null || showReview) {
          orders = orders.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['deliveryStatus'] ?? 'Processing';
            if (showReview) {
              final reviewed = data['reviewed'] == true;
              return status == 'Delivered' && !reviewed;
            }
            return status == statusFilter;
          }).toList();
        }

        if (orders.isEmpty) {
          return _buildEmptyState('No orders in this tab');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final orderDoc = orders[index];
            final orderData = orderDoc.data() as Map<String, dynamic>;
            final orderId = orderDoc.id;

            final rawItems = orderData['items'];
            final items = <Map<String, dynamic>>[];
            if (rawItems is List) {
              items.addAll(rawItems.map((e) => Map<String, dynamic>.from(e as Map)));
            } else if (rawItems is Map) {
              items.addAll(rawItems.values.map((e) => Map<String, dynamic>.from(e as Map)));
            }

            final total = (orderData['total'] ?? 0).toDouble();
            final status = orderData['deliveryStatus'] ?? 'Processing';
            final paymentMethod = (orderData['paymentMethod'] ?? 'cod').toString().toUpperCase();

            final firstItem = items.isNotEmpty ? items[0] : null;
            final productName = firstItem?['name'] ?? 'Unknown Product';
            final imageUrl = firstItem?['imageUrl'] ?? '';

            final itemCount = items.fold<int>(0, (sum, i) {
              final qty = i['quantity'];
              return sum + (qty is int ? qty : (qty is num ? qty.toInt() : 1));
            });

            return InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderDetailsScreen(orderId: orderId, orderData: orderData, items: items),
                  ),
                );
              },
              child: Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          imageUrl,
                          width: 80, height: 80, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80, height: 80, color: const Color(0xFF052238),
                            child: const Icon(Icons.image, color: Colors.white54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text('$itemCount ${itemCount > 1 ? 'items' : 'item'} • $paymentMethod', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_getStatusText(status), style: TextStyle(fontWeight: FontWeight.bold, color: _getStatusColor(status))),
                          const SizedBox(height: 6),
                          _buildActionButton(context, status, orderDoc, items, showReview),
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
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: 5,
      itemBuilder: (_, __) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(width: 80, height: 80, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 14, width: 120, color: Colors.grey[600]),
                    const SizedBox(height: 8),
                    Container(height: 12, width: 80, color: Colors.grey[600]),
                    const SizedBox(height: 8),
                    Container(height: 16, width: 60, color: Colors.grey[600]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.white54),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  String _getStatusText(String status) => switch (status) {
    'Processing' => 'Processing',
    'Shipped' => 'Out for delivery',
    'Delivered' => 'Delivered',
    'Cancelled' => 'Cancelled',
    _ => status,
  };

  Color _getStatusColor(String status) => switch (status) {
    'Processing' => Colors.orange,
    'Shipped' => Colors.blue,
    'Delivered' => Colors.green,
    'Cancelled' => Colors.red,
    _ => Colors.grey,
  };

  // ──────────────────────────────────────────────────────────────
// REPLACE THE ENTIRE _buildActionButton METHOD + ADD THESE TWO
// ──────────────────────────────────────────────────────────────

  Widget _buildActionButton(
    BuildContext context,
    String status,
    DocumentSnapshot orderDoc,
    List<Map<String, dynamic>> items,
    bool showReview,
  ) {
    final orderId = orderDoc.id;
    final orderData = orderDoc.data() as Map<String, dynamic>;

    // 1. Review button (Delivered + not reviewed)
    if (showReview) {
      return OutlinedButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReviewOrderScreen(orderId: orderId, items: items),
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: const Size(0, 0),
        ),
        child: const Text('Review', style: TextStyle(fontSize: 12)),
      );
    }

    // 2. Processing state — Check payment first!
    if (status == 'Processing') {
      final String paymentMethod = (orderData['paymentMethod'] ?? '').toString().toLowerCase();
      final String paymentStatus = (orderData['paymentStatus'] ?? '').toString();

      final bool isGcashPaid = paymentMethod == 'gcash' && paymentStatus == 'Paid';

      if (isGcashPaid) {
        // GCash already paid → Show "View Details" instead of Cancel
        return OutlinedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderDetailsScreen(
                  orderId: orderId,
                  orderData: orderData,
                  items: items,
                ),
              ),
            );
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: const Size(0, 0),
          ),
          child: const Text('View Details', style: TextStyle(fontSize: 12)),
        );
      }

      // Not paid → Show Cancel button
      return OutlinedButton(
        onPressed: () => _cancelOrder(context, orderId, items),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: const Size(0, 0),
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
        ),
        child: const Text('Cancel', style: TextStyle(fontSize: 12)),
      );
    }

    // 3. Delivered → Buy Again
    if (status == 'Delivered') {
      return OutlinedButton(
        onPressed: () => _buyAgain(context, items),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: const Size(0, 0),
        ),
        child: const Text('Buy Again', style: TextStyle(fontSize: 12)),
      );
    }

    // 4. Default (Shipped, Cancelled, etc.) → View Details
    return OutlinedButton(
      onPressed: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailsScreen(
              orderId: orderId,
              orderData: orderData,
              items: items,
            ),
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: const Size(0, 0),
      ),
      child: const Text('View Details', style: TextStyle(fontSize: 12)),
    );
  }

// ──────────────────────────────────────────────────────────────
// EXACT SAME LOGIC AS IN ORDER_DETAILS_SCREEN (NOW REUSED)
// ──────────────────────────────────────────────────────────────

Future<void> _cancelOrder(BuildContext context, String orderId, List<Map<String, dynamic>> items) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF052238),
      title: const Text('Cancel Order', style: TextStyle(color: Colors.white)),
      content: const Text('Are you sure you want to cancel this order?', style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('No', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirm != true || !context.mounted) return;

  try {
    // Fetch fresh order data to check payment method/status
    final orderDoc = await firestore
        .collection('orders')
        .doc(orderId)
        .get();

    if (!orderDoc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order not found'), backgroundColor: Colors.red),
      );
      return;
    }

    final paymentMethod = orderDoc['paymentMethod']?.toString() ?? 'cod';
    final paymentStatus = orderDoc['paymentStatus']?.toString() ?? 'Pending';

    final orderRef = orderDoc.reference;
    final batch = firestore.batch();

    if (paymentMethod == 'GCash' && paymentStatus == 'Paid') {
      // Trigger refund via Cloud Function
      try {
        await FirebaseFunctions.instance
            .httpsCallable('refundGcashPayment')
            .call({'orderId': orderId, 'reason': 'Customer cancelled'});

        // Only update Firestore after successful refund
        batch.update(orderRef, {
          'deliveryStatus': 'Cancelled',
          'paymentStatus': 'Refunded',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'Customer cancelled',
        });

        // Restore stock
        for (final item in items) {
          final productId = item['productId'] ?? item['id'];
          final qty = (item['quantity'] ?? 1) as int;
          if (productId != null && productId is String) {
            final productRef = firestore.collection('products').doc(productId);
            batch.update(productRef, {'stock': FieldValue.increment(qty)});
          }
        }

        await batch.commit();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order cancelled & refund processed!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Refund failed: $e'), backgroundColor: Colors.red),
          );
        }
        return; // Abort cancellation if refund fails
      }
    } else {
      // COD, unpaid GCash, or other → just cancel normally
      batch.update(orderRef, {
        'deliveryStatus': 'Cancelled',
        'paymentStatus': paymentMethod == 'GCash' ? 'Refunded' : 'Cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': 'Customer cancelled',
      });

      // Restore stock
      for (final item in items) {
        final productId = item['productId'] ?? item['id'];
        final qty = (item['quantity'] ?? 1) as int;
        if (productId != null && productId is String) {
          final productRef = firestore.collection('products').doc(productId);
          batch.update(productRef, {'stock': FieldValue.increment(qty)});
        }
      }

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order cancelled successfully!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel order: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

Future<void> _buyAgain(BuildContext context, List<Map<String, dynamic>> items) async {
  try {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final batch = firestore.batch();
    final cartItemsRef = firestore
        .collection('carts')
        .doc(userId)
        .collection('items');

    for (final item in items) {
      final docRef = cartItemsRef.doc(); // let Firestore generate ID
      batch.set(docRef, {
        'title': item['name'],
        'price': item['price'],
        'qty': item['quantity'],
        'imageUrl': item['imageUrl'],
        'productId': item['productId'],
        'addedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Items added to cart!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const cart.CartScreen()),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add to cart: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
}