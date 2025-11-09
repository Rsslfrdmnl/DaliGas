import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:daligas/screens/account_screen.dart';
import 'package:daligas/screens/cart_screen.dart' as cart;
import 'package:daligas/screens/help_screen.dart';
import 'package:daligas/screens/messages_screen.dart';
import 'package:daligas/screens/purchases_screen.dart';
import 'package:daligas/screens/search_screen.dart';
import 'package:daligas/screens/welcome_screen.dart';
import 'package:daligas/screens/product_detail_screen.dart';
import 'package:daligas/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:carousel_slider/carousel_slider.dart';


int tappedIndex = -1;

final GlobalKey<CartIconState> cartIconKey = GlobalKey<CartIconState>();

class CartIcon extends StatefulWidget {
  final VoidCallback onTap;
  final int itemCount;

  const CartIcon({
    super.key,
    required this.onTap,
    this.itemCount = 0,
  });

  @override
  CartIconState createState() => CartIconState();
}

class CartIconState extends State<CartIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _glowAnimation = ColorTween(begin: Colors.transparent, end: Colors.yellow)
        .animate(_controller);
  }

  void triggerGlowAndPop() {
    _controller.forward(from: 0).then((_) => _controller.reverse());
  }

  @override
  void didUpdateWidget(CartIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount > oldWidget.itemCount) {
      triggerGlowAndPop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _glowAnimation.value ?? Colors.transparent,
                  blurRadius: 15,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.shopping_bag_outlined,
                    color: Colors.white, size: 24),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  int _currentIndex = 0;
  int _currentCarouselIndex = 0;

  List<String> bannerImages = [];
  late final Stream<QuerySnapshot> _productStream;

  // ── Double-Back-to-Exit Logic ─────────────────────
  DateTime? _lastBackPress;
  static const int _backPressTimeout = 2; // seconds

  Future<bool> _onWillPop() async {
    final now = DateTime.now();

    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: _backPressTimeout)) {
      // First press → show toast
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.black87,
        ),
      );
      return false; // keep the screen
    }

    // Second press → **close the app**
    if (Platform.isAndroid) {
      SystemNavigator.pop(); // Android native exit
    } else {
      exit(0);               // iOS / other (force kill)
    }
    return true;
  }
  // ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fetchBannerImages();
    _productStream = FirebaseFirestore.instance.collection('products').snapshots();
  }

  Future<void> _fetchBannerImages() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('banners')
          .orderBy('order')
          .get();

      setState(() {
        bannerImages =
            snapshot.docs.map((doc) => doc['imageUrl'] as String).toList();
      });
    } catch (e) {
      debugPrint("Error loading banners: $e");
    }
  }

  Future<void> _signOut() async {
    setState(() => _isLoading = true);
    await _authService.signOut();
    setState(() => _isLoading = false);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  void _onNavTap(int index) {
    void instantNav(Widget page) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }

    setState(() => _currentIndex = index);
    switch (index) {
      case 0:
        break;
      case 1:
        instantNav(const MessagesScreen());
        break;
      case 2:
        instantNav(const PurchasesScreen(currentIndex: 2));
        break;
      case 3:
        instantNav(HelpScreen(currentIndex: 3));
        break;
      case 4:
        instantNav(const AccountScreen(currentIndex: 4));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = _authService.currentUser;

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
          title: const Text(
            'Home',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          actions: [
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.search, color: Colors.white),
              ),
            ),
            const SizedBox(width: 16),
            CartIcon(
              key: cartIconKey,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const cart.CartScreen()),
                );
              },
              itemCount: 0,
            ),
            const SizedBox(width: 12),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: Colors.white),
          ),
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
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
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home, color: Color(0xFF0D2236)),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline),
                activeIcon: Icon(Icons.chat_bubble, color: Color(0xFF0D2236)),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.shopping_bag_outlined),
                activeIcon: Icon(Icons.shopping_bag, color: Color(0xFF0D2236)),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.help_outline),
                activeIcon: Icon(Icons.help, color: Color(0xFF0D2236)),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person, color: Color(0xFF0D2236)),
                label: '',
              ),
            ],
          ),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Firestore Carousel
              if (bannerImages.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else
                Column(
                  children: [
                    CarouselSlider.builder(
                      itemCount: bannerImages.length,
                      itemBuilder: (context, index, realIdx) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            image: DecorationImage(
                              image: NetworkImage(bannerImages[index]),
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                      options: CarouselOptions(
                        height: 180,
                        autoPlay: true,
                        enlargeCenterPage: true,
                        viewportFraction: 0.9,
                        onPageChanged: (index, reason) {
                          setState(() => _currentCarouselIndex = index);
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: bannerImages.asMap().entries.map((entry) {
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _currentCarouselIndex = entry.key),
                          child: Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentCarouselIndex == entry.key
                                  ? Colors.white
                                  : Colors.white54,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),

              const Divider(height: 1, thickness: 1, color: Colors.white),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _productStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child:
                              CircularProgressIndicator(color: Colors.white),
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No products available',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      );
                    }

                    final products = snapshot.data!.docs;

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: products.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.8,
                      ),
                      itemBuilder: (context, index) {
                        final product =
                            products[index].data() as Map<String, dynamic>;
                        final name = product['name'] ?? 'Unnamed';
                        final price = product['price'] ?? 0;
                        final imageUrl =
                            product['imageUrl'] ??
                                'https://via.placeholder.com/300';

                        return GestureDetector(
                          onTapDown: (_) => setState(() => tappedIndex = index),
                          onTapUp: (_) => setState(() => tappedIndex = -1),
                          onTapCancel: () => setState(() => tappedIndex = -1),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductDetailScreen(
                                  product: {
                                    ...product,
                                    'id': products[index].id,
                                  },
                                ),
                              ),
                            );
                          },
                          child: AnimatedScale(
                            scale: tappedIndex == index ? 0.97 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: Stack(
                              children: [
                                AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF173B5F),
                                        Color(0xFF1E4975)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: tappedIndex == index
                                            ? Colors.black.withOpacity(0.3)
                                            : Colors.black.withOpacity(0.4),
                                        blurRadius:
                                            tappedIndex == index ? 6 : 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        flex: 7,
                                        child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top:
                                                      Radius.circular(16)),
                                          child: Container(
                                            color: const Color(0xFF0D2236),
                                            child: Image.network(
                                              imageUrl,
                                              fit: BoxFit.contain,
                                              width: double.infinity,
                                              errorBuilder:
                                                  (context, error, _) =>
                                                      const Center(
                                                child: Icon(
                                                    Icons
                                                        .image_not_supported,
                                                    color: Colors.grey,
                                                    size: 40),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8),
                                        child: Column(
                                          mainAxisSize:
                                              MainAxisSize.min,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              textAlign:
                                                  TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '₱${price.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight:
                                                    FontWeight.bold,
                                                color:
                                                    Color(0xFF1ED2AF),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            // Rating + Stocks
                                            StreamBuilder<QuerySnapshot>(
                                              stream: FirebaseFirestore
                                                  .instance
                                                  .collection(
                                                      'products')
                                                  .doc(products[index].id)
                                                  .collection('reviews')
                                                  .snapshots(),
                                              builder:
                                                  (context, snapshot) {
                                                double liveRating = 0.0;
                                                int reviewCount = 0;

                                                if (snapshot.hasData &&
                                                    snapshot.data!.docs
                                                        .isNotEmpty) {
                                                  final reviews =
                                                      snapshot.data!.docs;
                                                  reviewCount =
                                                      reviews.length;
                                                  final total = reviews
                                                      .fold<double>(
                                                    0.0,
                                                    (sum, doc) =>
                                                        sum +
                                                        ((doc['rating'] ??
                                                                    0)
                                                                as num)
                                                            .toDouble(),
                                                  );
                                                  liveRating =
                                                      reviewCount > 0
                                                          ? total /
                                                              reviewCount
                                                          : 0.0;
                                                }

                                                return Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .center,
                                                  children: [
                                                    const Icon(
                                                        Icons.star,
                                                        color: Colors
                                                            .amber,
                                                        size: 16),
                                                    const SizedBox(
                                                        width: 3),
                                                    Text(
                                                      liveRating
                                                          .toStringAsFixed(
                                                              1),
                                                      style:
                                                          const TextStyle(
                                                        color: Colors
                                                            .white70,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight
                                                                .w500,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                        width: 16),
                                                    Text(
                                                      'Stocks: ${(product['stock'] ?? 0)}',
                                                      style: TextStyle(
                                                        color: (product[
                                                                        'stock'] ??
                                                                    0) >
                                                                0
                                                            ? Colors
                                                                .white70
                                                            : Colors
                                                                .redAccent,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (product['isAvailable'] == false)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Unavailable',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
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
          ),
        ),
      ),
    );
  }
}