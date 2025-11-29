// lib/screens/order_details_screen.dart
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:daligas/screens/review_order_screen.dart';
import 'package:daligas/screens/cart_screen.dart' as cart;
import 'package:daligas/screens/chat_screen.dart';
import 'package:daligas/main_mobile.dart';

const String GOOGLE_MAPS_API_KEY = 'AIzaSyAVDDHYb29rt4io-HI0Uq6vfv_GAnlDLlw';

// ===================================================================
// FULL-SCREEN MAP (Customer View) - ROTATING TRUCK + DASHED ROUTE
// ===================================================================
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
  LatLng _driverLocation = const LatLng(14.5995, 120.9842);
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

  // ← FIX: Use passed driver location
  _driverLocation = widget.driverLocation;
  _previousLocation = _driverLocation;

  _loadDriverIconFromFirebase();
  _listenToDriverLocation();

  // Force initial marker + route
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _updateMarkers(); // ← ADD THIS
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
        _updateMarkers(); // ← ADD THIS
      }
    } catch (e) {
      debugPrint('Truck icon load failed: $e');
    }
  }

  void _listenToDriverLocation() {
    firestore
        .collection('orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
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

      _mapController?.animateCamera(CameraUpdate.newLatLng(newLoc));
      if (widget.customerLocation.latitude != 14.5995) _fetchRoute();
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
          rotation: rotation,
          zIndex: 10,
        ),
    };
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
      '&region=ph'
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
          setState(() => _routeInfo = '$duration • $distance');

          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: Colors.blue,
                width: 5,
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
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
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
      shift = 0; result = 0;
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
        title: Text('Live Tracking - #${widget.orderId.substring(widget.orderId.length - 12)}'),
        backgroundColor: const Color(0xFF052238),
        foregroundColor: Colors.white,
      ),
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

// ===================================================================
// ORDER DETAILS SCREEN - FULLY UPGRADED WITH EMPLOYEE-STYLE TRACKING
// ===================================================================
class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> orderData;
  final List<Map<String, dynamic>> items;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    required this.orderData,
    required this.items,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  GoogleMapController? _mapController;
  LatLng _driverLocation = const LatLng(14.5995, 120.9842);
  LatLng? _previousLocation;
  LatLng _customerLocation = const LatLng(14.5995, 120.9842);
  bool _isGeocoding = false;
  bool _isIconLoaded = false;
  bool _isRouteLoading = false;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  String _routeInfo = '';

  static BitmapDescriptor? _cachedTruckIcon;

  String? _driverPhone;
  String? _driverName;
  bool _isLoadingPhone = false;
  String _currentStatus = 'Processing';
  bool _hasReviewed = false;

  @override
  void initState() {
    super.initState();
    _loadDriverIconFromFirebase();
    _listenToDriverLocation();
    _geocodeCustomerAddress();
    _currentStatus = widget.orderData['deliveryStatus'] ?? 'Processing';
    _listenToOrderStatus();

    if (_currentStatus == 'Shipped') _fetchDriverInfo();
    if (_currentStatus == 'Delivered') _checkIfReviewed();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
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

  void _listenToDriverLocation() {
    firestore.collection('orders').doc(widget.orderId).snapshots().listen((doc) {
      if (!doc.exists || !mounted) return;
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

      _mapController?.animateCamera(CameraUpdate.newLatLng(newLoc));
      if (_customerLocation.latitude != 14.5995) _fetchRoute();
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
          rotation: rotation,
          zIndex: 10,
        ),
    };
  }

  void _listenToOrderStatus() {
    firestore.collection('orders').doc(widget.orderId).snapshots().listen((doc) {
      if (!doc.exists || !mounted) return;
      final data = doc.data()!;
      final newStatus = data['deliveryStatus'] as String? ?? 'Processing';
      if (newStatus != _currentStatus) {
        setState(() => _currentStatus = newStatus);
        if (newStatus == 'Shipped') _fetchDriverInfo();
        if (newStatus == 'Delivered' && !_hasReviewed) _checkIfReviewed();
      }
    });
  }

  Future<void> _geocodeCustomerAddress() async {
    final address = widget.orderData['deliveryAddress']?.toString() ?? '';
    if (address.isEmpty) return;

    final lat = widget.orderData['customerLatLng']?['lat'];
    final lng = widget.orderData['customerLatLng']?['lng'];
    if (lat != null && lng != null) {
      if (mounted) setState(() => _customerLocation = LatLng(lat as double, lng as double));
      return;
    }

    if (mounted) setState(() => _isGeocoding = true);
    try {
      final locations = await locationFromAddress('$address, Metro Manila, Philippines');
      if (locations.isNotEmpty && mounted) {
        final loc = locations.first;
        final newLoc = LatLng(loc.latitude, loc.longitude);
        setState(() => _customerLocation = newLoc);
        await firestore.collection('orders').doc(widget.orderId).update({
          'customerLatLng': {'lat': loc.latitude, 'lng': loc.longitude}
        });
      }
    } catch (e) {
      debugPrint('Geocoding failed: $e');
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  Future<void> _fetchRoute() async {
    if (_driverLocation.latitude == 14.5995 || _customerLocation.latitude == 14.5995 || _isRouteLoading) return;
    if (mounted) setState(() => _isRouteLoading = true);

    final origin = '${_driverLocation.latitude},${_driverLocation.longitude}';
    final destination = '${_customerLocation.latitude},${_customerLocation.longitude}';
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$origin'
      '&destination=$destination'
      '&mode=driving'
      '&region=ph'
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
          if (mounted) setState(() => _routeInfo = '$duration • $distance');

          if (mounted) {
            setState(() {
              _polylines = {
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: points,
                  color: Colors.blue,
                  width: 5,
                ),
              };
            });
          }
          _fitRouteOnMap(points);
        }
      }
    } catch (e) {
      debugPrint('Route fetch failed: $e');
    } finally {
      if (mounted) setState(() => _isRouteLoading = false);
    }
  }

  void _fitRouteOnMap(List<LatLng> points) {
    if (points.isEmpty || _mapController == null || !mounted) return;
    double minLat = points[0].latitude, maxLat = points[0].latitude;
    double minLng = points[0].longitude, maxLng = points[0].longitude;
    for (var p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
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
      shift = 0; result = 0;
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

  Future<void> _fetchDriverInfo() async {
    if (_isLoadingPhone) return;
    if (mounted) setState(() => _isLoadingPhone = true);
    try {
      final employeeId = widget.orderData['employeeId'] as String?;
      if (employeeId == null) return;

      final doc = await firestore.collection('employees').doc(employeeId).get();
      if (doc.exists && mounted) {
        setState(() {
          _driverPhone = doc['phone'] as String?;
          _driverName = doc['name'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch driver: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPhone = false);
    }
  }

  Future<void> _contactDriver() async {
    if (_driverPhone == null || _driverPhone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver phone not available')));
      return;
    }
    final uri = Uri(scheme: 'tel', path: _driverPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openDriverChat() {
    final employeeId = widget.orderData['employeeId'] as String?;
    if (employeeId == null) return;

    final userId = FirebaseAuth.instance.currentUser!.uid;
    final chatId = '${userId}_${employeeId}_${widget.orderId}';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: '${_driverName ?? 'Driver'} • Order #${_shortOrderId(widget.orderId)}',
          chatId: chatId,
          isEmployee: false,
          orderId: widget.orderId,
        ),
      ),
    );
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Order'),
        content: const Text('Are you sure you want to cancel this order?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final batch = firestore.batch();
      final orderRef = firestore.collection('orders').doc(widget.orderId);
      batch.update(orderRef, {'deliveryStatus': 'Cancelled', 'paymentStatus': 'Refunded'});

      for (final item in widget.items) {
        final productId = item['productId'];
        final qty = (item['quantity'] ?? 1) as int;
        final productRef = firestore.collection('products').doc(productId);
        batch.update(productRef, {'stock': FieldValue.increment(qty)});
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order cancelled and stocks restored!'), backgroundColor: Colors.orange));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel order: $e')));
    }
  }

  Future<void> _buyAgain() async {
    final batch = firestore.batch();
    final cartRef = firestore.collection('cart').doc(FirebaseAuth.instance.currentUser!.uid).collection('items');

    for (final item in widget.items) {
      final docRef = cartRef.doc();
      batch.set(docRef, {
        'title': item['name'],
        'price': item['price'],
        'qty': item['quantity'],
        'imageUrl': item['imageUrl'],
        'productId': item['productId'],
      });
    }

    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Items added to cart!'), backgroundColor: Colors.green));
      Navigator.push(context, MaterialPageRoute(builder: (_) => const cart.CartScreen()));
    }
  }

  Future<void> _checkIfReviewed() async {
    for (final item in widget.items) {
      final productId = item['productId'];
      final snap = await firestore
          .collection('products')
          .doc(productId)
          .collection('reviews')
          .where('orderId', isEqualTo: widget.orderId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty && mounted) {
        setState(() => _hasReviewed = true);
        return;
      }
    }
  }

  void _showReviewModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(color: Color(0xFF052238), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: ReviewOrderScreen(orderId: widget.orderId, items: widget.items),
      ),
    );
  }

  void _showFullMap() {
  if (_customerLocation.latitude == 14.5995) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Customer address still loading…')),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FullScreenMapScreen(
        orderId: widget.orderId,
        customerLocation: _customerLocation,
        driverLocation: _driverLocation, // ← ADD THIS
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final total = (widget.orderData['total'] ?? 0).toDouble();
    final status = _currentStatus;
    final address = widget.orderData['deliveryAddress'] ?? 'No address';
    final paymentMethod = (widget.orderData['paymentMethod'] ?? 'cod').toString().toUpperCase();
    final createdAt = (widget.orderData['createdAt'] as Timestamp?)?.toDate();

    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        backgroundColor: const Color(0xFF052238),
        title: const Text('Order Details'),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #${_shortOrderId(widget.orderId)}', 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                ),
                Flexible(
                  child: Text(createdAt != null ? _formatDate(createdAt) : '', style: const TextStyle(color: Colors.white70, fontSize: 14), overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: _getStatusColor(status))),
              child: Text(_getStatusText(status), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            const Text('Items', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white24),
            ...widget.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(item['imageUrl'] ?? '', width: 60, height: 60, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Container(width: 60, height: 60, color: Colors.white10, child: const Icon(Icons.image, color: Colors.white54))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['name'] ?? 'Product', style: const TextStyle(color: Colors.white)),
                    Text('Qty: ${item['quantity'] ?? 1}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                  Text('₱${(item['price'] ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            )),
            const Divider(color: Colors.white24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            const Text('Delivery Info', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
            const Text('Delivery Info', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _infoRow('Address', address),
            _infoRow('Payment', () {
              final paymentStatus = widget.orderData['paymentStatus']?.toString() ?? 'Pending';
              final paymentMethod = (widget.orderData['paymentMethod']?.toString() ?? 'cod').toLowerCase();

              if (paymentStatus == 'Paid') {
                return 'Paid via GCash';
              } else if (paymentStatus == 'Refunded') {
                return 'Refunded to GCash';
              } else if (paymentMethod == 'gcash') {
                return 'GCash (Pending)';
              } else {
                return 'Cash on Delivery';
              }
            }()),
            const SizedBox(height: 24),
            const Text('Delivery Timeline', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _timelineStep('Order Placed', true),
            _timelineStep('Processing', status != 'Processing'),
            _timelineStep('Shipped', status == 'Shipped' || status == 'Delivered'),
            _timelineStep('Delivered', status == 'Delivered', isLast: true),

            if (status == 'Shipped') ...[
              const SizedBox(height: 16),
              const Text('Live Tracking', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
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
                            if (mounted && _driverLocation.latitude != 14.5995 && _customerLocation.latitude != 14.5995) {
                              _fetchRoute();
                            }
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
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // === Cancel Button Logic (Only show if Processing + NOT paid via GCash) ===
if (status == 'Processing')
                () {
                  final bool isGcashPaid = (widget.orderData['paymentMethod']?.toString().toLowerCase() == 'gcash') &&
                                           (widget.orderData['paymentStatus']?.toString() == 'Paid');

                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isGcashPaid ? null : _cancelOrder,
                      icon: Icon(
                        isGcashPaid ? Icons.lock_outline : Icons.cancel_outlined,
                        size: 20,
                      ),
                      label: Text(
                        isGcashPaid
                            ? 'Cancellation Not Allowed'
                            : 'Cancel Order',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isGcashPaid
                              ? Colors.white.withOpacity(0.45)
                              : null,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isGcashPaid
                            ? Colors.white.withOpacity(0.08)     // Very subtle fill (transparent look)
                            : const Color(0xFF8B0000),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white.withOpacity(0.08),
                        disabledForegroundColor: Colors.white.withOpacity(0.45),
                        side: isGcashPaid
                            ? BorderSide(color: Colors.white.withOpacity(0.2), width: 1)
                            : BorderSide.none,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  );
                }(),

              // === Delivered: Buy Again + Review ===
              if (status == 'Delivered') ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _buyAgain,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Buy Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _hasReviewed ? null : _showReviewModal,
                    icon: Icon(
                      Icons.rate_review_outlined,
                      color: _hasReviewed ? Colors.grey : Colors.blue,
                    ),
                    label: Text(
                      _hasReviewed ? 'Review Submitted' : 'Leave a Review',
                      style: TextStyle(color: _hasReviewed ? Colors.grey : Colors.blue),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _hasReviewed ? Colors.grey : Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],

              // === Shipped: Contact Driver + Chat ===
              if (_currentStatus == 'Shipped') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _driverPhone != null ? _contactDriver : null,
                    icon: _isLoadingPhone
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.phone, color: Colors.white),
                    label: Text(
                      _isLoadingPhone
                          ? 'Loading driver...'
                          : _driverName != null
                              ? 'Contact $_driverName ($_driverPhone)'
                              : _driverPhone != null
                                  ? 'Contact Driver ($_driverPhone)'
                                  : 'Driver phone unavailable',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      elevation: 3,
                      shadowColor: Colors.blue.withOpacity(0.4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _driverName != null ? _openDriverChat : null,
                    icon: const Icon(Icons.chat, color: Colors.white),
                    label: Text(
                      _driverName != null ? 'Chat with $_driverName' : 'Loading driver...',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      elevation: 3,
                      shadowColor: Colors.green.withOpacity(0.4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: value.contains('Paid') || value == 'Paid'
                  ? Colors.green
                  : value.contains('Refunded')
                      ? Colors.orange
                      : Colors.white70,
              fontWeight: value.contains('Paid') || value.contains('Refunded')
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontSize: 15,
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _timelineStep(String title, bool completed, {bool isLast = false}) {
    return Row(children: [
      Column(children: [
        Icon(completed ? Icons.check_circle : Icons.radio_button_unchecked, color: completed ? Colors.green : Colors.white54, size: 20),
        if (!isLast) Container(width: 2, height: 40, color: Colors.white24),
      ]),
      const SizedBox(width: 12),
      Text(title, style: TextStyle(color: completed ? Colors.white : Colors.white54)),
    ]);
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

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _shortOrderId(String fullId) {
  if (fullId.length > 12) {
    return '${fullId.substring(0, 12)}...';
  }
  return fullId;
 }
}