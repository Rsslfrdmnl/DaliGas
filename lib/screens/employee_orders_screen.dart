import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
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
import 'package:daligas/screens/employee_account_screen.dart';
import 'package:daligas/screens/chat_screen.dart';

// REPLACE WITH YOUR GOOGLE MAPS API KEY
const String GOOGLE_MAPS_API_KEY = 'AIzaSyAVDDHYb29rt4io-HI0Uq6vfv_GAnlDLlw';

class EmployeeOrdersScreen extends StatefulWidget {
  final int currentIndex;
  const EmployeeOrdersScreen({super.key, this.currentIndex = 0});

  @override
  State<EmployeeOrdersScreen> createState() => _EmployeeOrdersScreenState();
}

class _EmployeeOrdersScreenState extends State<EmployeeOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final User? _employee = FirebaseAuth.instance.currentUser;
  Position? _currentPosition;
  Timer? _locationThrottle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initLocation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _locationThrottle?.cancel();
    super.dispose();
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
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _currentPosition = position);

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 50,
        ),
      ).listen((pos) {
        if (_locationThrottle?.isActive ?? false) return;
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

    FirebaseFirestore.instance
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
        }).catchError((e) => debugPrint('Update failed: $e'));
      }
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream() {
    if (_employee == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('orders')
        .where('employeeId', isEqualTo: _employee!.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
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
        title: Text(
          'Order #$orderId',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '$product $weight × $qty',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 2),
            Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor(status)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
        ),
      ),
    );
  }

  Widget _empty(String msg) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 60, color: Colors.white54),
            const SizedBox(height: 16),
            Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _bottomNav() => Theme(
        data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Location Disabled"),
        content: const Text("Please enable location services to track deliveries."),
        actions: [
          TextButton(
            onPressed: () => Geolocator.openLocationSettings(),
            child: const Text("Open Settings"),
          ),
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
        actions: [
          TextButton(onPressed: openAppSettings, child: const Text("Open Settings")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        backgroundColor: const Color(0xFF052238),
        elevation: 0,
        titleSpacing: -8,
        leading: const SizedBox.shrink(),
        title: const Text('My Shipments', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, thickness: 1, color: Colors.white24)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _ordersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _empty('No orders assigned to you');

          final orders = snapshot.data!.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

          final processing = orders.where((o) => o['deliveryStatus'] == 'Processing').toList();
          final shipped = orders.where((o) => o['deliveryStatus'] == 'Shipped').toList();
          final completed = orders.where((o) => o['deliveryStatus'] == 'Delivered').toList();
          final pending = [...processing, ...shipped];

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))]),
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF052238),
                  unselectedLabelColor: Colors.black54,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  indicator: BoxDecoration(color: const Color(0xFFe6eef7), borderRadius: BorderRadius.circular(12)),
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [Tab(text: 'Pending'), Tab(text: 'Completed')],
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
    );
  }
}

// ================================================================
// BOTTOM-SHEET: WAZE-STYLE ROUTE + CONSISTENT TRUCK ICON
// ================================================================
class _OrderActionsSheet extends StatefulWidget {
  final String orderId;
  final String status;
  final List<Map<String, dynamic>> items;
  final String userId;
  final String deliveryAddress;
  final VoidCallback onStatusChanged;
  final Position? currentPosition;
  final Map<String, dynamic> orderData;

  const _OrderActionsSheet({
    required this.orderId,
    required this.status,
    required this.items,
    required this.userId,
    required this.deliveryAddress,
    required this.onStatusChanged,
    this.currentPosition,
    required this.orderData,
  });

  @override
  State<_OrderActionsSheet> createState() => _OrderActionsSheetState();
}

class _OrderActionsSheetState extends State<_OrderActionsSheet> {
  GoogleMapController? _mapController;
  LatLng _driverLocation = const LatLng(14.5995, 120.9842);
  LatLng _customerLocation = const LatLng(14.5995, 120.9842);
  String? _customerPhone;
  bool _isGeocoding = false;
  bool _isIconLoaded = false;
  bool _isRouteLoading = false;
  Set<Polyline> _polylines = {};
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
        final codec = await ui.instantiateImageCodec(
          response.bodyBytes,
          targetWidth: 150,
          targetHeight: 150,
        );
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
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    if (doc.exists) setState(() => _customerPhone = doc['phone'] as String?);
  }

  void _listenToDriverLocation() {
    FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots().listen((doc) {
      if (!doc.exists) return;
      final data = doc.data()!;
      final lat = data['driverLocation']?['lat'];
      final lng = data['driverLocation']?['lng'];
      if (lat == null || lng == null) return;

      final newLoc = LatLng(lat as double, lng as double);
      final oldLoc = _driverLocation;

      setState(() => _driverLocation = newLoc);

      if (_customerLocation.latitude != 14.5995 && _customerLocation.longitude != 120.9842 &&
          (oldLoc.latitude != newLoc.latitude || oldLoc.longitude != newLoc.longitude)) {
        _fetchRoute();
      }

      _mapController?.animateCamera(CameraUpdate.newLatLng(newLoc));
    });
  }

  void _loadCustomerLocation() async {
    final lat = widget.orderData['customerLatLng']?['lat'];
    final lng = widget.orderData['customerLatLng']?['lng'];
    if (lat != null && lng != null) {
      setState(() => _customerLocation = LatLng(lat as double, lng as double));
      if (_driverLocation.latitude != 14.5995) {
        _fetchRoute();
      }
      return;
    }

    if (widget.deliveryAddress.isEmpty) return;
    setState(() => _isGeocoding = true);
    try {
      final locations = await locationFromAddress(widget.deliveryAddress);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final newCustomerLoc = LatLng(loc.latitude, loc.longitude);
        setState(() => _customerLocation = newCustomerLoc);

        // Save to Firestore
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .update({
          'customerLatLng': {'lat': loc.latitude, 'lng': loc.longitude}
        });

        if (_driverLocation.latitude != 14.5995) {
          _fetchRoute();
        }
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
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$origin'
      '&destination=$destination'
      '&mode=driving'
      '&key=$GOOGLE_MAPS_API_KEY'
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      debugPrint('Directions URL: $url');
      debugPrint('Response: ${response.statusCode}');

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
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: Colors.blue,
                width: 5,
                patterns: [PatternItem.dash(30), PatternItem.gap(10)],
              ),
            };
          });

          _fitRouteOnMap(points);
        } else {
          debugPrint('API Error: ${data['status']} - ${data['error_message']}');
          _showError('No route found');
        }
      }
    } catch (e) {
      debugPrint('Route fetch failed: $e');
      _showError('Failed to load route');
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

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

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

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _shortOrderId(String fullId) {
  if (fullId.length <= 5) return fullId;
  return fullId.substring(fullId.length - 5);
}

  Future<void> _confirmOrder() async {
    try {
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
      await orderRef.update({
        'deliveryStatus': 'Shipped',
        'driverLocation': {
          'lat': widget.currentPosition?.latitude ?? 14.5995,
          'lng': widget.currentPosition?.longitude ?? 120.9842,
        },
      });
      await _notifyCustomer('Out for delivery', 'Your order #${widget.orderId} is on its way!');
      widget.onStatusChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to confirm: $e')));
    }
  }

  Future<void> _confirmDelivery() async {
    try {
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
      await orderRef.update({'deliveryStatus': 'Delivered'});
      await _notifyCustomer('Delivered', 'Order #${widget.orderId} has been delivered.');
      widget.onStatusChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to confirm: $e')));
    }
  }

  Future<void> _notifyCustomer(String title, String body) async {
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).collection('inAppNotifications').add({
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
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showFullMap() {
    if (_customerLocation.latitude == 14.5995) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer address still loading...')));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenMapScreen(
          orderId: widget.orderId,
          customerLocation: _customerLocation,
          driverLocation: _driverLocation,
        ),
      ),
    );
  }

  void _showContactOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone, color: Color(0xFF052238)),
              title: const Text('Call Customer'),
              onTap: () { Navigator.pop(context); _callCustomer(); },
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: Color(0xFF052238)),
              title: const Text('Chat with Customer'),
              onTap: () {
                Navigator.pop(context);
                final chatId = _generateChatId();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      title: 'Customer • Order #${_shortOrderId(widget.orderId)}',
                      chatId: chatId,
                      isEmployee: true,
                      orderId: widget.orderId, // optional: for future use
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  String _generateChatId() {
  final employeeId = FirebaseAuth.instance.currentUser!.uid;
  final customerId = widget.orderData['userId'] as String;
  return '${customerId}_${employeeId}_${widget.orderId}'; // CUSTOMER FIRST
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
                    Text('${widget.items.length} item${widget.items.length > 1 ? 's' : ''}', style: const TextStyle(color: Colors.grey)),
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
                      markers: {
                        Marker(
                          markerId: const MarkerId('customer'),
                          position: _customerLocation,
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        ),
                        if (_isIconLoaded && _cachedTruckIcon != null)
                          Marker(
                            markerId: const MarkerId('driver'),
                            position: _driverLocation,
                            icon: _cachedTruckIcon!,
                            anchor: const Offset(0.5, 0.5),
                          ),
                      },
                      polylines: _polylines,
                      onMapCreated: (c) {
                        _mapController = c;
                        Future.delayed(const Duration(milliseconds: 500), () {
                          if (_driverLocation.latitude != 14.5995 && _customerLocation.latitude != 14.5995) {
                            _fetchRoute();
                          }
                        });
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                    ),
                    if (_isRouteLoading)
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
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
                    icon: const Icon(Icons.check, size: 20),
                    label: const Text('Confirm Order'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF052238), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _confirmOrder,
                  ),
                ),
              if (canConfirmDelivery) const SizedBox(width: 12),
              if (canConfirmDelivery)
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle, size: 20),
                    label: const Text('Confirm Delivery'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _confirmDelivery,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.contact_phone, color: Color(0xFF052238)),
              label: Text(
                _customerPhone != null ? 'Contact Customer ($_customerPhone)' : 'Loading...',
                style: const TextStyle(color: Color(0xFF052238)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF052238), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _customerPhone != null ? _showContactOptions : null,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ================================================================
// FULL-SCREEN MAP: WAZE-STYLE ROUTE
// ================================================================
class FullScreenMapScreen extends StatefulWidget {
  final String orderId;
  final LatLng customerLocation;
  final LatLng driverLocation;

  const FullScreenMapScreen({
    super.key,
    required this.orderId,
    required this.customerLocation,
    required this.driverLocation,
  });

  @override
  State<FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<FullScreenMapScreen> {
  GoogleMapController? _mapController;
  LatLng _driverLocation;
  bool _isIconLoaded = false;
  bool _isRouteLoading = false;
  Set<Polyline> _polylines = {};
  String _routeInfo = '';
  static BitmapDescriptor? _cachedTruckIcon;

  _FullScreenMapScreenState() : _driverLocation = const LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    _driverLocation = widget.driverLocation;
    _loadDriverIconFromFirebase();
    _listenToDriverLocation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_driverLocation.latitude != 14.5995 && widget.customerLocation.latitude != 14.5995) {
        _fetchRoute();
      }
    });
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
      if (response.statusCode != 200) return;

      final codec = await ui.instantiateImageCodec(
        response.bodyBytes,
        targetWidth: 150,
        targetHeight: 150,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      final bitmap = BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
      _cachedTruckIcon = bitmap;

      if (mounted) setState(() => _isIconLoaded = true);
    } catch (e) {
      debugPrint('Truck icon load failed: $e');
    }
  }

  void _listenToDriverLocation() {
    FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final data = doc.data()!;
      final lat = data['driverLocation']?['lat'];
      final lng = data['driverLocation']?['lng'];
      if (lat != null && lng != null) {
        final newLoc = LatLng(lat as double, lng as double);
        setState(() {
          _driverLocation = newLoc;
          _fetchRoute();
        });
        _mapController?.animateCamera(CameraUpdate.newLatLng(newLoc));
      }
    });
  }

  Future<void> _fetchRoute() async {
    if (_driverLocation.latitude == 14.5995 || widget.customerLocation.latitude == 14.5995 || _isRouteLoading) return;

    setState(() => _isRouteLoading = true);

    final origin = '${_driverLocation.latitude},${_driverLocation.longitude}';
    final destination = '${widget.customerLocation.latitude},${widget.customerLocation.longitude}';
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$origin'
      '&destination=$destination'
      '&mode=driving'
      '&key=$GOOGLE_MAPS_API_KEY'
    );

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
            _polylines = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: Colors.blue,
                width: 5,
                patterns: [PatternItem.dash(30), PatternItem.gap(10)],
              ),
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
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Tracking - #${widget.orderId}'),
        backgroundColor: const Color(0xFF052238),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: widget.customerLocation, zoom: 14),
            markers: {
              Marker(
                markerId: const MarkerId('customer'),
                position: widget.customerLocation,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              ),
              if (_isIconLoaded && _cachedTruckIcon != null)
                Marker(
                  markerId: const MarkerId('driver'),
                  position: _driverLocation,
                  icon: _cachedTruckIcon!,
                  anchor: const Offset(0.5, 0.5),
                ),
            },
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            onMapCreated: (c) => _mapController = c,
          ),
          if (_isRouteLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_routeInfo.isNotEmpty)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(16)),
                child: Text(_routeInfo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}