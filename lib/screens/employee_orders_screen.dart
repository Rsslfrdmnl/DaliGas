// UPDATED SCREEN - WITH FULL ORDER DETAILS BUTTON + MEMORY LEAK FIX
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, exit;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:daligas/screens/employee_account_screen.dart';
import 'package:daligas/screens/chat_screen.dart';
import 'package:flutter/services.dart';
import 'package:daligas/main_mobile.dart';

const String GOOGLE_MAPS_API_KEY = 'AIzaSyAVDDHYb29rt4io-HI0Uq6vfv_GAnlDLlw';

class EmployeeOrdersScreen extends StatefulWidget {
  final int currentIndex;
  const EmployeeOrdersScreen({super.key, this.currentIndex = 0});

  @override
  State<EmployeeOrdersScreen> createState() => _EmployeeOrdersScreenState();
}

class _EmployeeOrdersScreenState extends State<EmployeeOrdersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final User? _employee = FirebaseAuth.instance.currentUser;
  Position? _currentPosition;
  Timer? _locationThrottle;
  StreamSubscription<Position>? _positionStream;

  DateTime? _lastBackPress;

  // SAFE SUBJECTS + PREVENT DUPLICATE LISTENERS
  late BehaviorSubject<int> _pendingCountSubject;
  late BehaviorSubject<int> _completedCountSubject;
  StreamSubscription<QuerySnapshot>? _orderChangesSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);

    _pendingCountSubject = BehaviorSubject<int>.seeded(0);
    _completedCountSubject = BehaviorSubject<int>.seeded(0);

    _initLocation();
    _listenToOrderChanges();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLocation();
    }
  }

  // PERMANENTLY FIXED — NO DUPLICATES, NO LEAKS
  void _listenToOrderChanges() {
    if (_employee == null) return;

    _orderChangesSubscription?.cancel();

    _orderChangesSubscription = firestore
        .collection('orders')
        .where('employeeId', isEqualTo: _employee!.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (_pendingCountSubject.isClosed || _completedCountSubject.isClosed) return;

      final orders = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      final pending = orders.where((o) => o['deliveryStatus'] == 'Processing' || o['deliveryStatus'] == 'Shipped').length;
      final completed = orders.where((o) => o['deliveryStatus'] == 'Delivered').length;

      _pendingCountSubject.add(pending);
      _completedCountSubject.add(completed);
    });
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationServiceDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showPermissionDeniedDialog();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showPermissionPermanentlyDeniedDialog();
      return;
    }

    try {
      await _positionStream?.cancel();
      _positionStream = null;

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => _currentPosition = position);

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50),
      ).listen((pos) {
        if (!mounted || (_locationThrottle?.isActive ?? false)) return;
        _locationThrottle = Timer(const Duration(seconds: 30), () {});

        setState(() => _currentPosition = pos);
        _updateDriverLocation(pos);
      });
    } catch (e) {
      debugPrint('Location init failed: $e');
    }
  }

  void _updateDriverLocation(Position position) {
    if (_employee == null) return;

    firestore
        .collection('orders')
        .where('employeeId', isEqualTo: _employee!.uid)
        .where('deliveryStatus', isEqualTo: 'Shipped')
        .get()
        .then((snapshot) {
      for (var doc in snapshot.docs) {
        doc.reference.update({
          'driverLocation': {
            'lat': position.latitude,
            'lng': position.longitude,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _locationThrottle?.cancel();
    _positionStream?.cancel();

    _orderChangesSubscription?.cancel();
    _pendingCountSubject.close();
    _completedCountSubject.close();

    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Processing': return Colors.orange;
      case 'Shipped': return Colors.blue;
      case 'Delivered': return Colors.green;
      case 'Cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final String orderId = order['id'];
    final double total = (order['total'] ?? 0).toDouble();
    final String status = order['deliveryStatus'] ?? 'Processing';
    final String address = order['deliveryAddress'] ?? '—';

    final List itemsRaw = order['items'] ?? [];
    final Map? first = itemsRaw.isNotEmpty ? itemsRaw[0] : null;
    final String product = first?['name'] ?? 'Product';
    final int qty = first?['quantity'] ?? 1;
    final String weight = first?['weight']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFF052238),
          child: Icon(
            status == 'Delivered' ? Icons.check_circle : Icons.local_shipping_outlined,
            color: Colors.white,
            size: 28,
          ),
        ),
        title: Text('Order #$orderId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('$product $weight × $qty', style: const TextStyle(fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 2),
            Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor(status)),
                  ),
                  child: Text(status, style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white),
        onTap: () => _showOrderBottomSheet(order),
      ),
    );
  }

  void _showOrderBottomSheet(Map<String, dynamic> order) {
    final String orderId = order['id'];
    final String status = order['deliveryStatus'] ?? 'Processing';
    final String address = order['deliveryAddress'] ?? '';
    final List itemsRaw = order['items'] ?? [];
    final String userId = order['userId'] as String;

    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      itemsRaw.map((e) => Map<String, dynamic>.from(e as Map)),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: null,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
child: _OrderActionsSheet(
  orderId: orderId,
  status: status,
  items: items,
  userId: userId,
  deliveryAddress: address,
  onStatusChanged: () => setState(() {}),
  currentPosition: _currentPosition,
  orderData: order,
  onShowDetails: () => _showOrderDetails(order), // ← Pass the function
),
      ),
    );
  }

  // NEW: Full Order Details Bottom Sheet
  void _showOrderDetails(Map<String, dynamic> order) {
    final String orderId = order['id'];
    final double total = (order['total'] ?? 0).toDouble();
    final String paymentMethod = order['paymentMethod'] ?? 'Unknown';
    final String paymentStatus = order['paymentStatus'] ?? 'Pending';
    final String deliveryAddress = order['deliveryAddress'] ?? 'Not provided';
    final Timestamp? createdAt = order['createdAt'] as Timestamp?;
    final List items = order['items'] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: null,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.6,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 16),
              Text('Order Details', style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Order #$orderId', style: const TextStyle(fontSize: 16, color: Colors.white)),
              const Divider(height: 32),
              const Text('Items Ordered', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final String name = item['name'] ?? 'Unknown';
                    final String weight = item['weight']?.toString() ?? '';
                    final double price = (item['price'] ?? 0).toDouble();
                    final int qty = item['quantity'] ?? 1;
                    final double subtotal = price * qty;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text('$weight × $qty', style: const TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                            Text('₱${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 32),
              _buildDetailRow('Total Amount', '₱${total.toStringAsFixed(2)}', isBold: true),
              _buildDetailRow('Payment Method', paymentMethod),
              _buildDetailRow('Payment Status', paymentStatus, color: paymentStatus == 'Paid' ? Colors.green : Colors.orange),
              _buildDetailRow('Delivery Address', deliveryAddress),
              if (createdAt != null) _buildDetailRow('Order Date', _formatTimestamp(createdAt)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.white))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? Colors.black))),
        ],
      ),
    );
  }

String _formatTimestamp(Timestamp timestamp) {
  final date = timestamp.toDate();
  final monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  final month = monthNames[date.month - 1];
  final day = date.day;
  final year = date.year;

  final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';

  return '$month $day, $year ${hour}:${minute}$period';
}

  Widget _empty(String msg) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 60, color: Colors.white54),
            const SizedBox(height: 16),
            Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _bottomNav() => Theme(
        data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: null,
          currentIndex: widget.currentIndex,
          selectedItemColor: const Color(0xFF0D2236),
          unselectedItemColor: Colors.black54,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          onTap: (i) {
            if (i == widget.currentIndex) return;
            if (i == 1) {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(pageBuilder: (_, __, ___) => const EmployeeAccountScreen(currentIndex: 1), transitionDuration: Duration.zero),
              );
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), activeIcon: Icon(Icons.local_shipping, color: Color(0xFF0D2236)), label: ''),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person, color: Color(0xFF0D2236)), label: ''),
          ],
        ),
      );

  void _showLocationServiceDialog() {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Location Disabled"),
        content: const Text("Please enable location services to track deliveries."),
        actions: [
          TextButton(onPressed: () async { Navigator.pop(context); await Geolocator.openLocationSettings(); }, child: const Text("Open Settings")),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Permission Required"),
        content: const Text("Location access is needed for delivery tracking."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: Geolocator.requestPermission, child: const Text("Allow")),
        ],
      ),
    );
  }

  void _showPermissionPermanentlyDeniedDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Permission Denied"),
        content: const Text("Please enable location in Settings > Apps > DaliGas > Permissions."),
        actions: [TextButton(onPressed: openAppSettings, child: const Text("Open Settings"))],
      ),
    );
  }

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2), backgroundColor: Colors.black87));
      return false;
    }
    if (Platform.isAndroid) SystemNavigator.pop();
    else exit(0);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF052238),
        appBar: AppBar(
          backgroundColor: const Color(0xFF052238),
          elevation: 0,
          titleSpacing: -8,
          leading: const SizedBox.shrink(),
          title: const Text('My Shipments', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, thickness: 1, color: Colors.white24)),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _employee != null
              ? firestore
                  .collection('orders')
                  .where('employeeId', isEqualTo: _employee!.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots()
              : const Stream.empty(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _empty('No orders assigned to you');
            }

            final orders = snapshot.data!.docs.map((doc) {
              final data = doc.data()! as Map<String, dynamic>;
              data['id'] = doc.id;
              return data;
            }).toList();

            final pending = orders.where((o) => o['deliveryStatus'] == 'Processing' || o['deliveryStatus'] == 'Shipped').toList();
            final completed = orders.where((o) => o['deliveryStatus'] == 'Delivered').toList();

            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF052238),
                    unselectedLabelColor: Colors.black54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    indicator: BoxDecoration(color: const Color(0xFFe6eef7), borderRadius: BorderRadius.circular(12)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Pending'),
                            const SizedBox(width: 6),
                            StreamBuilder<int>(
                              stream: _pendingCountSubject.stream,
                              builder: (context, snapshot) {
                                final count = snapshot.data ?? 0;
                                if (count == 0) return const SizedBox();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                                  child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Completed'),
                            const SizedBox(width: 6),
                            StreamBuilder<int>(
                              stream: _completedCountSubject.stream,
                              builder: (context, snapshot) {
                                final count = snapshot.data ?? 0;
                                if (count == 0) return const SizedBox();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                                  child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      pending.isEmpty ? _empty('No pending orders') : ListView.builder(padding: const EdgeInsets.only(top: 8), itemCount: pending.length, itemBuilder: (_, i) => _buildOrderCard(pending[i])),
                      completed.isEmpty ? _empty('No completed orders') : ListView.builder(padding: const EdgeInsets.only(top: 8), itemCount: completed.length, itemBuilder: (_, i) => _buildOrderCard(completed[i])),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: _bottomNav(),
      ),
    );
  }
}

// BOTTOM-SHEET: WAZE-STYLE + NAVIGATION BUTTON
class _OrderActionsSheet extends StatefulWidget {
  final String orderId;
  final String status;
  final List<Map<String, dynamic>> items;
  final String userId;
  final String deliveryAddress;
  final VoidCallback onStatusChanged;
  final Position? currentPosition;
  final Map<String, dynamic> orderData;
  final VoidCallback onShowDetails;

  const _OrderActionsSheet({
    required this.orderId,
    required this.status,
    required this.items,
    required this.userId,
    required this.deliveryAddress,
    required this.onStatusChanged,
    this.currentPosition,
    required this.orderData,
    required this.onShowDetails,
  });

  @override
  State<_OrderActionsSheet> createState() => _OrderActionsSheetState();
}

class _OrderActionsSheetState extends State<_OrderActionsSheet> {
  GoogleMapController? _mapController;
  LatLng _driverLocation = const LatLng(14.5995, 120.9842);
  LatLng _customerLocation = const LatLng(14.5995, 120.9842);
  LatLng? _previousLocation;
  String? _customerPhone;
  bool _isGeocoding = false;
  bool _isIconLoaded = false;
  bool _isRouteLoading = false;
  bool _isConfirmingOrder = false;
  bool isConfirmingDelivery = false;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  String _routeInfo = '';

  static BitmapDescriptor? _cachedTruckIcon;

  @override
  void initState() {
    super.initState();
    _loadDriverIconFromFirebase();
    _fetchCustomerPhone();
    _listenToDriverLocation();
    _loadCustomerLocation();
  }

Widget _buildFullOrderDetailsSheet({
  required Map<String, dynamic> orderData,
  required ScrollController scrollController,
}) {
  final String orderId = orderData['id'] ?? 'Unknown';
  final double total = (orderData['total'] ?? 0).toDouble();
  final String paymentMethod = orderData['paymentMethod'] ?? 'Unknown';
  final String paymentStatus = orderData['paymentStatus'] ?? 'Pending';
  final String deliveryAddress = orderData['deliveryAddress'] ?? 'Not provided';
  final Timestamp? createdAt = orderData['createdAt'] as Timestamp?;
  final List items = orderData['items'] ?? [];

  return Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Order Details', style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Order #$orderId', style: const TextStyle(fontSize: 16, color: Colors.white)),
        const Divider(height: 32),

        const Text('Items Ordered', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),

        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final String name = item['name'] ?? 'Unknown';
              final String weight = item['weight']?.toString() ?? '';
              final double price = (item['price'] ?? 0).toDouble();
              final int qty = item['quantity'] ?? 1;
              final double subtotal = price * qty;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('$weight × $qty', style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      Text('₱${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const Divider(height: 32),
        _buildDetailRow('Total Amount', '₱${total.toStringAsFixed(2)}', isBold: true),
        _buildDetailRow('Payment Method', paymentMethod),
        _buildDetailRow('Payment Status', paymentStatus,
            color: paymentStatus == 'Paid' ? Colors.green : Colors.orange),
        _buildDetailRow('Delivery Address', deliveryAddress),
        if (createdAt != null)
          _buildDetailRow('Order Date', _formatTimestamp(createdAt)),
        const SizedBox(height: 20),
      ],
    ),
  );
}

// Reuse your existing helper methods
Widget _buildDetailRow(String label, String value, {bool isBold = false, Color? color}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.white))),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? Colors.black,
            ),
          ),
        ),
      ],
    ),
  );
}

String _formatTimestamp(Timestamp timestamp) {
  final date = timestamp.toDate();
  final monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  final month = monthNames[date.month - 1];
  final day = date.day;
  final year = date.year;
  final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '$month $day, $year ${hour}:${minute}$period';
}

  Future<void> _loadDriverIconFromFirebase() async {
    if (_cachedTruckIcon != null) {
      setState(() => _isIconLoaded = true);
      return;
    }
    try {
      final ref = FirebaseStorage.instance.ref().child('icons/truck.png');
      final url = await ref.getDownloadURL();
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(response.bodyBytes, targetWidth: 150, targetHeight: 150);
        final frame = await codec.getNextFrame();
        final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        final bitmap = BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
        _cachedTruckIcon = bitmap;
        if (mounted) setState(() => _isIconLoaded = true);
      }
    } catch (e) {
      debugPrint('Failed to load truck icon: $e');
    }
  }

  void _fetchCustomerPhone() async {
    final doc = await firestore.collection('users').doc(widget.userId).get();
    if (doc.exists) setState(() => _customerPhone = doc['phone'] as String?);
  }

  void _listenToDriverLocation() {
    firestore.collection('orders').doc(widget.orderId).snapshots().listen((doc) {
      if (!doc.exists) return;
      final data = doc.data()!;
      final lat = data['driverLocation']?['lat'];
      final lng = data['driverLocation']?['lng'];
      if (lat == null || lng == null) return;

      final newLoc = LatLng(lat as double, lng as double);
      setState(() {
        _previousLocation = _driverLocation;
        _driverLocation = newLoc;
        _updateMarkers();
      });

      if (_customerLocation.latitude != 14.5995 &&
          (_previousLocation == null || _previousLocation!.latitude != newLoc.latitude || _previousLocation!.longitude != newLoc.longitude)) {
        _fetchRoute();
      }
      _mapController?.animateCamera(CameraUpdate.newLatLng(newLoc));
    });
  }

  void _updateMarkers() {
    double rotation = 0;
    if (_previousLocation != null) {
      rotation = Geolocator.bearingBetween(
        _previousLocation!.latitude,
        _previousLocation!.longitude,
        _driverLocation.latitude,
        _driverLocation.longitude,
      );
    }

    _markers = {
      Marker(markerId: const MarkerId('customer'), position: _customerLocation, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
      if (_isIconLoaded && _cachedTruckIcon != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverLocation,
          icon: _cachedTruckIcon!,
          anchor: const Offset(0.5, 0.5),
          rotation: rotation,
          zIndex: 10,
        ),
    };
  }

  void _loadCustomerLocation() async {
    final lat = widget.orderData['customerLatLng']?['lat'];
    final lng = widget.orderData['customerLatLng']?['lng'];
    if (lat != null && lng != null) {
      setState(() {
        _customerLocation = LatLng(lat as double, lng as double);
        _updateMarkers();
      });
      if (_driverLocation.latitude != 14.5995) _fetchRoute();
      return;
    }

    if (widget.deliveryAddress.isEmpty) return;
    setState(() => _isGeocoding = true);
    try {
      final locations = await locationFromAddress(widget.deliveryAddress);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final newCustomerLoc = LatLng(loc.latitude, loc.longitude);
        setState(() {
          _customerLocation = newCustomerLoc;
          _updateMarkers();
        });

        await firestore.collection('orders').doc(widget.orderId).update({
          'customerLatLng': {'lat': loc.latitude, 'lng': loc.longitude}
        });

        if (_driverLocation.latitude != 14.5995) _fetchRoute();
      }
    } catch (e) {
      debugPrint('Geocoding failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Address not found: $e')));
    } finally {
      setState(() => _isGeocoding = false);
    }
  }

  Future<void> _fetchRoute() async {
    if (_driverLocation.latitude == 14.5995 || _customerLocation.latitude == 14.5995 || _isRouteLoading) return;

    setState(() => _isRouteLoading = true);

    final origin = '${_driverLocation.latitude},${_driverLocation.longitude}';
    final destination = '${_customerLocation.latitude},${_customerLocation.longitude}';

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&mode=driving&key=$GOOGLE_MAPS_API_KEY',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final encoded = data['routes'][0]['overview_polyline']['points'];
          final points = _decodePoly(encoded);

          final legs = data['routes'][0]['legs'][0];
          final distance = legs['distance']['text'];
          final duration = legs['duration']['text'];
          _routeInfo = '$duration • $distance';

          setState(() {
            _polylines = {
              Polyline(polylineId: const PolylineId('route'), points: points, color: Colors.blue, width: 5),
            };
          });
          _fitRouteOnMap(points);
        }
      }
    } catch (e) {
      debugPrint('Route fetch failed: $e');
    } finally {
      setState(() => _isRouteLoading = false);
    }
  }

  void _fitRouteOnMap(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;

    double minLat = points[0].latitude, maxLat = points[0].latitude;
    double minLng = points[0].longitude, maxLng = points[0].longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  List<LatLng> _decodePoly(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  void _launchNavigation() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTip = prefs.getBool('nav_tip_shown') ?? false;

    if (!hasSeenTip && mounted) {
      await prefs.setBool('nav_tip_shown', true);
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Navigation Tip', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('We\'ll open Waze first (best for PH traffic).\n\nIf Waze is not installed, Google Maps will open automatically.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Got it!', style: TextStyle(fontWeight: FontWeight.bold)))],
        ),
      );
      if (confirmed != true) return;
    }

    final originLat = _driverLocation.latitude;
    final originLng = _driverLocation.longitude;
    final destLat = _customerLocation.latitude;
    final destLng = _customerLocation.longitude;

    final wazeUri = Uri.parse('waze://?ll=$destLat,$destLng&navigate=yes');
    final googleUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$destLat,$destLng&travelmode=driving&dir_action=navigate',
    );

    bool opened = false;
    try { opened = await launchUrl(wazeUri, mode: LaunchMode.externalApplication); } catch (_) {}
    if (!opened) {
      try {
        await launchUrl(googleUri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Waze not found. Opening Google Maps...'), backgroundColor: Colors.blue, duration: Duration(seconds: 2)));
        }
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening in browser...')));
      }
    }
  }

  String _shortOrderId(String fullId) => fullId.length <= 5 ? fullId : fullId.substring(fullId.length - 5);

  Future<void> _confirmOrder() async {
    if (_isConfirmingOrder) return;
    setState(() => _isConfirmingOrder = true);

    try {
      final orderRef = firestore.collection('orders').doc(widget.orderId);
      await orderRef.update({
        'deliveryStatus': 'Shipped',
        'driverLocation': {
          'lat': widget.currentPosition?.latitude ?? 14.5995,
          'lng': widget.currentPosition?.longitude ?? 120.9842,
        },
        'shippedAt': FieldValue.serverTimestamp(),
      });

      await _notifyCustomer('Out for delivery', 'Your order #${widget.orderId} is on its way!');
      widget.onStatusChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm order: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirmingOrder = false);
    }
  }

  Future<void> _confirmDelivery() async {
  if (isConfirmingDelivery) return;
  setState(() => isConfirmingDelivery = true);

  try {
    final orderRef = firestore.collection('orders').doc(widget.orderId);

    // Use a transaction to safely check current paymentStatus and update only if needed
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) throw Exception("Order not found");

      final currentPaymentStatus = snapshot.get('paymentStatus') as String? ?? 'Pending';

      // Build the update map
      final updateData = <String, dynamic>{
        'deliveryStatus': 'Delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
      };

      // Only set paymentStatus to "Paid" if it's not already Paid
      if (currentPaymentStatus != 'Paid') {
        updateData['paymentStatus'] = 'Paid';
        updateData['paidAt'] = FieldValue.serverTimestamp(); // optional: track when it was marked paid
      }

      transaction.update(orderRef, updateData);
    });

    // Notify customer
    await _notifyCustomer('Order Delivered!', 'Your order #${widget.orderId} has been successfully delivered and payment is confirmed.');

    widget.onStatusChanged();
    if (mounted) Navigator.pop(context);
  } catch (e) {
    debugPrint('Confirm delivery failed: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to confirm delivery: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => isConfirmingDelivery = false);
  }
}

  Future<void> _notifyCustomer(String title, String body) async {
    await firestore.collection('users').doc(widget.userId).collection('inAppNotifications').add({
      'title': title,
      'body': body,
      'type': 'order',
      'orderId': widget.orderId,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  Future<void> _callCustomer() async {
    if (_customerPhone == null || _customerPhone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer phone not available')));
      return;
    }
    final uri = Uri(scheme: 'tel', path: _customerPhone);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showFullMap() {
    if (_customerLocation.latitude == 14.5995) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer address still loading...')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullScreenMapScreen(
        orderId: widget.orderId,
        customerLocation: _customerLocation,
        driverLocation: _driverLocation,
      ),
    ));
  }

  void _showContactOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.phone, color: Color(0xFF052238)), title: const Text('Call Customer'), onTap: () { Navigator.pop(context); _callCustomer(); }),
            ListTile(
              leading: const Icon(Icons.chat, color: Color(0xFF052238)),
              title: const Text('Chat with Customer'),
              onTap: () {
                Navigator.pop(context);
                final chatId = '${widget.orderData['userId']}_${FirebaseAuth.instance.currentUser!.uid}_${widget.orderId}';
                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(title: 'Customer • Order #${_shortOrderId(widget.orderId)}', chatId: chatId, isEmployee: true, orderId: widget.orderId)));
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canConfirmOrder = widget.status == 'Processing';
    final bool canConfirmDelivery = widget.status == 'Shipped';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF052238),
                child: Icon(widget.status == 'Delivered' ? Icons.check_circle : Icons.local_shipping_outlined, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #${widget.orderId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    Text('${widget.items.length} item${widget.items.length > 1 ? 's' : ''}', style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (widget.status == 'Shipped') ...[
            const Text('Live Tracking', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 10),
            Container(
              height: 180,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.blue, width: 2)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(target: _customerLocation, zoom: 15),
                      markers: _markers,
                      polylines: _polylines,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      onMapCreated: (c) {
                        _mapController = c;
                        Future.delayed(const Duration(milliseconds: 500), () {
                          if (_driverLocation.latitude != 14.5995 && _customerLocation.latitude != 14.5995) _fetchRoute();
                        });
                      },
                    ),
                    if (_isRouteLoading) const Center(child: CircularProgressIndicator(color: Colors.white)),
                    if (_routeInfo.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                          child: Text(_routeInfo, style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _showFullMap,
                icon: const Icon(Icons.fullscreen, size: 16, color: Colors.blue),
                label: const Text('Tap to expand', style: TextStyle(color: Colors.blue, fontSize: 12)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              if (canConfirmOrder)
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isConfirmingOrder
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check, size: 20),
                    label: Text(_isConfirmingOrder ? 'Confirming...' : 'Confirm Order'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF052238), foregroundColor: null, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _isConfirmingOrder ? null : _confirmOrder,
                  ),
                ),

              if (canConfirmOrder || canConfirmDelivery) const SizedBox(width: 8),
              Expanded(
  child: ElevatedButton.icon(
    icon: const Icon(Icons.receipt_long, size: 20),
    label: const Text('See Details'),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.deepPurple,
      foregroundColor: null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(vertical: 14),
    ),
    onPressed: () {
      // DO NOT pop the current sheet! Just open a new one on top
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: null,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.6,
          builder: (_, controller) => _buildFullOrderDetailsSheet(
            orderData: widget.orderData,
            scrollController: controller,
          ),
        ),
      );
    },
  ),
),

              if (canConfirmDelivery) const SizedBox(width: 8),
              if (canConfirmDelivery)
                Expanded(
                  child: ElevatedButton.icon(
                    icon: isConfirmingDelivery ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle, size: 20),
                    label: Text(isConfirmingDelivery ? 'Confirming...' : 'Confirm Delivery'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: null, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: isConfirmingDelivery ? null : _confirmDelivery,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.contact_phone, color: Color(0xFF052238)),
              label: Text(_customerPhone != null ? 'Contact Customer ($_customerPhone)' : 'Loading...', style: const TextStyle(color: Color(0xFF052238))),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF052238), width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _customerPhone != null ? _showContactOptions : null,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// FULL-SCREEN MAP
class FullScreenMapScreen extends StatefulWidget {
  final String orderId;
  final LatLng customerLocation;
  final LatLng driverLocation;

  const FullScreenMapScreen({super.key, required this.orderId, required this.customerLocation, required this.driverLocation});

  @override
  State<FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<FullScreenMapScreen> {
  GoogleMapController? _mapController;
  late LatLng _driverLocation;
  LatLng? _previousLocation;
  bool _isIconLoaded = false;
  bool _isRouteLoading = false;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  String _routeInfo = '';
  static BitmapDescriptor? _cachedTruckIcon;

  @override
  void initState() {
    super.initState();
    _driverLocation = widget.driverLocation;
    _previousLocation = widget.driverLocation;
    _loadDriverIconFromFirebase();
    _listenToDriverLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_driverLocation.latitude != 14.5995 && widget.customerLocation.latitude != 14.5995) _fetchRoute();
    });
  }

  Future<void> _loadDriverIconFromFirebase() async {
    if (_cachedTruckIcon != null) { setState(() => _isIconLoaded = true); return; }
    try {
      final ref = FirebaseStorage.instance.ref().child('icons/truck.png');
      final url = await ref.getDownloadURL();
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(response.bodyBytes, targetWidth: 150, targetHeight: 150);
        final frame = await codec.getNextFrame();
        final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        final bitmap = BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
        _cachedTruckIcon = bitmap;
        if (mounted) setState(() => _isIconLoaded = true);
      }
    } catch (e) {
      debugPrint('Truck icon load failed: $e');
    }
  }

  void _listenToDriverLocation() {
    firestore.collection('orders').doc(widget.orderId).snapshots().listen((doc) {
      if (!doc.exists) return;
      final data = doc.data()!;
      final lat = data['driverLocation']?['lat'];
      final lng = data['driverLocation']?['lng'];
      if (lat != null && lng != null) {
        final newLoc = LatLng(lat as double, lng as double);
        setState(() {
          _previousLocation = _driverLocation;
          _driverLocation = newLoc;
          _updateMarkers();
          _fetchRoute();
        });
        _mapController?.animateCamera(CameraUpdate.newLatLng(newLoc));
      }
    });
  }

  void _updateMarkers() {
    double rotation = 0;
    if (_previousLocation != null) {
      rotation = Geolocator.bearingBetween(_previousLocation!.latitude, _previousLocation!.longitude, _driverLocation.latitude, _driverLocation.longitude);
    }
    _markers = {
      Marker(markerId: const MarkerId('customer'), position: widget.customerLocation, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
      if (_isIconLoaded && _cachedTruckIcon != null)
        Marker(markerId: const MarkerId('driver'), position: _driverLocation, icon: _cachedTruckIcon!, anchor: const Offset(0.5, 0.5), rotation: rotation, zIndex: 10),
    };
  }

  Future<void> _fetchRoute() async {
    if (_driverLocation.latitude == 14.5995 || widget.customerLocation.latitude == 14.5995 || _isRouteLoading) return;
    setState(() => _isRouteLoading = true);

    final origin = '${_driverLocation.latitude},${_driverLocation.longitude}';
    final destination = '${widget.customerLocation.latitude},${widget.customerLocation.longitude}';
    final url = Uri.parse('https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&mode=driving&key=$GOOGLE_MAPS_API_KEY');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final points = _decodePoly(data['routes'][0]['overview_polyline']['points']);
          final legs = data['routes'][0]['legs'][0];
          final distance = legs['distance']['text'];
          final duration = legs['duration']['text'];
          _routeInfo = '$duration • $distance';

          setState(() {
            _polylines = {Polyline(polylineId: const PolylineId('route'), points: points, color: Colors.blue, width: 5)};
          });
          _fitRouteOnMap(points);
        }
      }
    } catch (e) {
      debugPrint('Route fetch failed: $e');
    } finally {
      setState(() => _isRouteLoading = false);
    }
  }

  void _fitRouteOnMap(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    double minLat = points[0].latitude, maxLat = points[0].latitude;
    double minLng = points[0].longitude, maxLng = points[0].longitude;
    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final bounds = LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  List<LatLng> _decodePoly(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  void _launchNavigation() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTip = prefs.getBool('nav_tip_shown') ?? false;
    if (!hasSeenTip && mounted) {
      await prefs.setBool('nav_tip_shown', true);
      final confirmed = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Navigation Tip', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('We\'ll open Waze first (best for PH traffic).\n\nIf Waze is not installed, Google Maps will open automatically.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Got it!', style: TextStyle(fontWeight: FontWeight.bold)))],
      ));
      if (confirmed != true) return;
    }

    final wazeUri = Uri.parse('waze://?ll=${widget.customerLocation.latitude},${widget.customerLocation.longitude}&navigate=yes');
    final googleUri = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=${_driverLocation.latitude},${_driverLocation.longitude}&destination=${widget.customerLocation.latitude},${widget.customerLocation.longitude}&travelmode=driving&dir_action=navigate');

    bool opened = false;
    try { opened = await launchUrl(wazeUri, mode: LaunchMode.externalApplication); } catch (_) {}
    if (!opened) {
      try {
        await launchUrl(googleUri, mode: LaunchMode.externalApplication);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Waze not found. Opening Google Maps...'), backgroundColor: Colors.blue, duration: Duration(seconds: 2)));
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening in browser...')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Live Tracking - #${widget.orderId}'), backgroundColor: const Color(0xFF052238), foregroundColor: null),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: widget.customerLocation, zoom: 14),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            onMapCreated: (c) => _mapController = c,
          ),
          if (_isRouteLoading) const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_routeInfo.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)]),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.access_time, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(_routeInfo.split('•').first.trim(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(' • ${_routeInfo.split('•').last.trim()}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _launchNavigation,
        backgroundColor: Colors.green,
        icon: const Icon(Icons.navigation, size: 28),
        label: const Text('START NAVIGATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}