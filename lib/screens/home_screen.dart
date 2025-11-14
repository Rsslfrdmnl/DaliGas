import 'dart:async';
import 'dart:io';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:daligas/screens/account_screen.dart';
import 'package:daligas/screens/cart_screen.dart' as cart;
import 'package:daligas/screens/help_screen.dart';
import 'package:daligas/screens/messages_screen.dart';
import 'package:daligas/screens/purchases_screen.dart';
import 'package:daligas/screens/search_screen.dart';
import 'package:daligas/screens/product_detail_screen.dart';
import 'package:daligas/screens/manage_address_screen.dart';
import 'package:daligas/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

int tappedIndex = -1;
final GlobalKey<CartIconState> cartIconKey = GlobalKey<CartIconState>();

class CartIcon extends StatefulWidget {
  final VoidCallback onTap;
  final int itemCount;
  const CartIcon({super.key, required this.onTap, this.itemCount = 0});
  @override
  CartIconState createState() => CartIconState();
}

class CartIconState extends State<CartIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _glowAnimation = ColorTween(begin: Colors.transparent, end: Colors.yellow).animate(_controller);
  }

  void triggerGlowAndPop() => _controller.forward(from: 0).then((_) => _controller.reverse());

  @override
  void didUpdateWidget(CartIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount > oldWidget.itemCount) triggerGlowAndPop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _glowAnimation.value ?? Colors.transparent, blurRadius: 15, spreadRadius: 3)],
              ),
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 24)),
              ),
            ),
            if (widget.itemCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text(
                    '${widget.itemCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  int _currentIndex = 0;
  int _currentCarouselIndex = 0;

  List<String> bannerImages = [];
  LatLng? _userLocation;
  Map<String, dynamic>? _activeAddress;

  final StreamController<LatLng?> _locationController = StreamController<LatLng?>.broadcast();
  late final Stream<List<DocumentSnapshot>> _nearbyProductsStream;

  // Reactive cart count with rxdart
  late final BehaviorSubject<int> _cartCountSubject;

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  String _lpgPriceMin = "";
  String _lpgPriceMax = "";
  String _lpgLastChecked = "";
  bool _lpgPriceLoading = true;

  bool _addressLoading = true;

  static const double MAX_DISTANCE_KM = 5.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchBannerImages();
    _loadActiveAddress();
    _loadLpgPriceFromFirestore();

    _nearbyProductsStream = _getNearbyProductsStream().shareReplay(maxSize: 1);

    // Initialize reactive cart count
    _cartCountSubject = BehaviorSubject<int>.seeded(0);

    // Listen to cart changes in real-time
    final user = _authService.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('carts')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        final items = (snapshot.data()?['items'] as List?)?.length ?? 0;
        if (_cartCountSubject.valueOrNull != items) {
          _cartCountSubject.add(items);
        }
      });
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (_userLocation != null && mounted) {
        _locationController.add(_userLocation);
      }
    });
  }

  @override
  void dispose() {
    _cartCountSubject.close();
    _locationController.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadActiveAddress();
      _loadLpgPriceFromFirestore();
    }
  }

  Future<void> _loadActiveAddress() async {
    setState(() => _addressLoading = true);
    final user = _authService.currentUser;
    if (user == null) {
      setState(() {
        _activeAddress = null;
        _userLocation = null;
        _addressLoading = false;
      });
      _locationController.add(null);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists || doc['addresses'] == null || (doc['addresses'] as List).isEmpty) {
        setState(() {
          _activeAddress = null;
          _userLocation = null;
          _addressLoading = false;
        });
        _locationController.add(null);
        return;
      }

      final addresses = List<Map<String, dynamic>>.from(doc['addresses']);
      final active = addresses.firstWhereOrNull((a) => a['isActive'] == true);

      setState(() {
        _activeAddress = active;
        _addressLoading = false;
        if (active != null && active['lat'] != null && active['lng'] != null) {
          _userLocation = LatLng(active['lat'] as double, active['lng'] as double);
        } else {
          _userLocation = null;
        }
        _locationController.add(_userLocation);
      });
    } catch (e) {
      debugPrint("Error loading address: $e");
      setState(() {
        _activeAddress = null;
        _userLocation = null;
        _addressLoading = false;
      });
      _locationController.add(null);
    }
  }

  Future<void> _loadLpgPriceFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('doe_latest')
          .doc('lpg')
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final Timestamp? timestamp = data['lastChecked'] as Timestamp?;
        String formattedDate = "Unknown";

        if (timestamp != null) {
          final DateTime date = timestamp.toDate().toLocal();
          formattedDate = "${_getMonthName(date.month)} ${date.day}, ${date.year}";
        }

        setState(() {
          _lpgPriceMin = data['pricePerKgMin']?.toString() ?? "";
          _lpgPriceMax = data['pricePerKgMax']?.toString() ?? "";
          _lpgLastChecked = formattedDate;
          _lpgPriceLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading LPG price: $e");
      setState(() => _lpgPriceLoading = false);
    }
  }

  double _calculateDistance(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude) / 1000;
  }

  Future<void> _fetchBannerImages() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('banners').orderBy('order').get();
      setState(() {
        bannerImages = snapshot.docs.map((doc) => doc['imageUrl'] as String).toList();
      });
    } catch (e) {
      debugPrint("Banner error: $e");
    }
  }

  void _onNavTap(int index) {
    void instantNav(Widget page) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(pageBuilder: (_, __, ___) => page, transitionDuration: Duration.zero),
      );
    }

    setState(() => _currentIndex = index);
    switch (index) {
      case 0: break;
      case 1: instantNav(const MessagesScreen()); break;
      case 2: instantNav(const PurchasesScreen(currentIndex: 2)); break;
      case 3: instantNav(HelpScreen(currentIndex: 3)); break;
      case 4: instantNav(const AccountScreen(currentIndex: 4)); break;
    }
  }

  DateTime? _lastBackPress;
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2), backgroundColor: Colors.black87),
      );
      return false;
    }
    if (Platform.isAndroid) SystemNavigator.pop();
    else exit(0);
    return true;
  }

  Stream<List<DocumentSnapshot>> _getNearbyProductsStream() {
    return _locationController.stream
        .where((loc) => loc != null)
        .distinct()
        .switchMap((loc) {
          return GeoCollectionReference(FirebaseFirestore.instance.collection('products'))
              .subscribeWithin(
                center: GeoFirePoint(GeoPoint(loc!.latitude, loc.longitude)),
                radiusInKm: MAX_DISTANCE_KM,
                field: 'location',
                geopointFrom: (data) {
                  final locationMap = data['location'] as Map<String, dynamic>?;
                  final geo = locationMap?['geopoint'];
                  if (geo is GeoPoint) return geo;
                  return const GeoPoint(0, 0);
                },
                strictMode: true,
              );
        });
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
          title: const Text('Home', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          actions: [
            // ORIGINAL: Opens SearchScreen
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.search, color: Colors.white)),
            ),
            const SizedBox(width: 16),
            // Reactive Cart Badge with rxdart
            StreamBuilder<int>(
              stream: _cartCountSubject.stream,
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return CartIcon(
                  key: cartIconKey,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const cart.CartScreen())),
                  itemCount: count,
                );
              },
            ),
            const SizedBox(width: 12),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageAddressScreen()));
                    if (result == true) await _loadActiveAddress();
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: Colors.white, size: 24),
                            const SizedBox(width: 8),
                            _addressLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                  )
                                : Text(
                                    _activeAddress != null
                                        ? '${_activeAddress!['street'] ?? 'No street'}'.trim()
                                        : 'Set your delivery address',
                                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                          ],
                        ),
                        Expanded(
                          child: _lpgPriceLoading
                              ? const Align(
                                  alignment: Alignment.centerRight,
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text('LPG Price per kg', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w500)),
                                    Text('As of $_lpgLastChecked', style: const TextStyle(color: Colors.white60, fontSize: 8)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _lpgPriceMin.isNotEmpty && _lpgPriceMax.isNotEmpty
                                          ? '₱$_lpgPriceMin - ₱$_lpgPriceMax'
                                          : 'Price N/A',
                                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Colors.white),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            currentIndex: _currentIndex,
            selectedItemColor: const Color(0xFF0D2236),
            unselectedItemColor: Colors.black,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            onTap: _onNavTap,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), activeIcon: Icon(Icons.shopping_bag, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.help_outline), activeIcon: Icon(Icons.help, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person, color: Color(0xFF0D2236)), label: ''),
            ],
          ),
        ),
        // 1. Pull-to-Refresh
        body: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              _loadActiveAddress(),
              _loadLpgPriceFromFirestore(),
              _fetchBannerImages(),
            ]);
          },
          color: Colors.cyan,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 16),
                if (bannerImages.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.white)))
                else
                  Column(
                    children: [
                      CarouselSlider.builder(
                        itemCount: bannerImages.length,
                        itemBuilder: (context, index, realIdx) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            image: DecorationImage(image: NetworkImage(bannerImages[index]), fit: BoxFit.cover),
                          ),
                        ),
                        options: CarouselOptions(
                          height: 180,
                          autoPlay: true,
                          enlargeCenterPage: true,
                          viewportFraction: 0.9,
                          onPageChanged: (index, reason) => setState(() => _currentCarouselIndex = index),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: bannerImages.asMap().entries.map((e) => GestureDetector(
                          onTap: () => setState(() => _currentCarouselIndex = e.key),
                          child: Container(
                            width: 8, height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: _currentCarouselIndex == e.key ? Colors.white : Colors.white54),
                          ),
                        )).toList(),
                      ),
                    ],
                  ),

                if (_addressLoading) ...[
                  const SizedBox(height: 100),
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                ]
                else if (_activeAddress == null) ...[
                  const SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const Icon(Icons.location_off, size: 80, color: Colors.white54),
                        const SizedBox(height: 24),
                        const Text('Want to buy gas? Let\'s find shops near you!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        const Text('Tap the address above to add or activate your delivery address', style: TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageAddressScreen()));
                            if (result == true) await _loadActiveAddress();
                          },
                          icon: const Icon(Icons.location_on),
                          label: const Text('Manage Addresses'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1ED2AF), padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                        ),
                      ],
                    ),
                  ),
                ]
                else ...[
                  const Divider(height: 1, thickness: 1, color: Colors.white),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: StreamBuilder<List<DocumentSnapshot>>(
                      key: ValueKey(_userLocation),
                      stream: _userLocation == null ? const Stream.empty() : _nearbyProductsStream,
                      builder: (context, snapshot) {
                        // 3. Skeleton Loading
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: 6,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.8,
                            ),
                            itemBuilder: (_, __) => const _SkeletonProductCard(),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  const Icon(Icons.storefront, size: 60, color: Colors.white54),
                                  const SizedBox(height: 16),
                                  Text('No shops within ${MAX_DISTANCE_KM.toInt()}km', style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                                  TextButton(
                                    onPressed: () async {
                                      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageAddressScreen()));
                                      if (result == true) await _loadActiveAddress();
                                    },
                                    child: const Text('Change Address', style: TextStyle(color: Colors.cyan)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final nearby = snapshot.data!;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: nearby.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.8,
                          ),
                          itemBuilder: (context, index) {
                            final doc = nearby[index];
                            final product = doc.data() as Map<String, dynamic>;
                            final name = product['name'] ?? 'Unnamed';
                            final price = product['price'] ?? 0;
                            final imageUrl = product['imageUrl'] ?? 'https://via.placeholder.com/300';

                            double distance = 0;
                            if (_userLocation != null && product['location'] != null) {
                              final locationMap = product['location'] as Map<String, dynamic>;
                              final geo = locationMap['geopoint'] as GeoPoint?;
                              if (geo != null) {
                                final shopLatLng = LatLng(geo.latitude, geo.longitude);
                                distance = _calculateDistance(_userLocation!, shopLatLng);
                              }
                            }

                            final distanceText = distance < 1
                                ? '${(distance * 1000).toStringAsFixed(0)} m away'
                                : '${distance.toStringAsFixed(1)} km away';

                            return GestureDetector(
                              onTapDown: (_) => setState(() => tappedIndex = index),
                              onTapUp: (_) => setState(() => tappedIndex = -1),
                              onTapCancel: () => setState(() => tappedIndex = -1),
                              // 10. Haptic Feedback
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ProductDetailScreen(product: {...product, 'id': doc.id})),
                                );
                              },
                              child: AnimatedScale(
                                scale: tappedIndex == index ? 0.97 : 1.0,
                                duration: const Duration(milliseconds: 150),
                                child: Stack(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Color(0xFF173B5F), Color(0xFF1E4975)]),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [BoxShadow(color: tappedIndex == index ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.4), blurRadius: tappedIndex == index ? 6 : 10, offset: const Offset(0, 4))],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            flex: 7,
                                            child: ClipRRect(
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                              child: Container(
                                                color: const Color(0xFF0D2236),
                                                child: Image.network(imageUrl, fit: BoxFit.contain, width: double.infinity,
                                                  errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            child: Column(
                                              children: [
                                                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                                                ),
                                                const SizedBox(height: 4),
                                                Text('₱${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1ED2AF))),
                                                const SizedBox(height: 6),
                                                StreamBuilder<QuerySnapshot>(
                                                  stream: FirebaseFirestore.instance.collection('products').doc(doc.id).collection('reviews').snapshots(),
                                                  builder: (context, snapshot) {
                                                    double rating = 0.0;
                                                    if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                                      final reviews = snapshot.data!.docs;
                                                      rating = reviews.fold(0.0, (sum, r) => sum + (r['rating'] as num).toDouble()) / reviews.length;
                                                    }
                                                    return Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        const Icon(Icons.star, color: Colors.amber, size: 16),
                                                        const SizedBox(width: 3),
                                                        Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                                        const SizedBox(width: 16),
                                                        Text('Stocks: ${product['stock'] ?? 0}', style: TextStyle(color: (product['stock'] ?? 0) > 0 ? Colors.white70 : Colors.redAccent, fontSize: 12)),
                                                      ],
                                                    );
                                                  },
                                                ),
                                                if (distance > 0) ...[
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      const Icon(Icons.location_on, size: 12, color: Colors.white70),
                                                      const SizedBox(width: 4),
                                                      Text(distanceText, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (product['isAvailable'] == false)
                                      Positioned(
                                        top: 8, right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                                          child: const Text('Unavailable', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 3. Skeleton Card
class _SkeletonProductCard extends StatelessWidget {
  const _SkeletonProductCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Expanded(flex: 7, child: Container(color: Colors.grey[700])),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Container(height: 14, width: 100, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Container(height: 16, width: 60, color: Colors.grey[600]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}