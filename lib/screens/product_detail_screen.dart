import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:daligas/services/cart_service.dart';
import 'package:daligas/screens/checkout_screen.dart';
import 'package:daligas/screens/home_screen.dart' show cartIconKey;
import 'package:daligas/screens/all_reviews_screen.dart';
import 'package:daligas/screens/all_comments_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:daligas/main_mobile.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> with TickerProviderStateMixin {
  final CartService _cartService = CartService();
  final GlobalKey _imageKey = GlobalKey();
  final TextEditingController _commentController = TextEditingController();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final ImagePicker _picker = ImagePicker();

  bool _isAddingToCart = false;
  bool _isPostingComment = false;
  bool _uploading = false;
  List<XFile> _selectedImages = [];

  late final String productId;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    productId = widget.product['id'] as String;
    _scrollController = ScrollController();

    // Ensure layout is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        // Ready for scroll
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _animateAndPop(BuildContext context, String imageUrl) async {
    final overlay = Overlay.of(context);
    final renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    final cartRenderBox = cartIconKey.currentContext?.findRenderObject() as RenderBox?;

    if (overlay == null || renderBox == null || cartRenderBox == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final imagePosition = renderBox.localToGlobal(Offset.zero);
    final imageSize = renderBox.size;
    final cartPosition = cartRenderBox.localToGlobal(Offset.zero);
    final cartSize = cartRenderBox.size;

    final adjustedCartPosition = cartPosition.translate(
      cartSize.width * -1.7,
      cartSize.height * -1.2,
    );

    final entry = OverlayEntry(
      builder: (_) => AnimatedImageToCart(
        startPosition: imagePosition,
        endPosition: adjustedCartPosition,
        imageUrl: imageUrl,
        imageSize: imageSize,
      ),
    );

    overlay.insert(entry);

    if (mounted) {
      Navigator.of(context).pop();
    }

    await Future.delayed(const Duration(milliseconds: 900));
    cartIconKey.currentState?.triggerGlowAndPop();
    await Future.delayed(const Duration(milliseconds: 300));
    if (entry.mounted) entry.remove();
  }

  // PICK IMAGES (FIXED: imageQuality + deprecated API)
  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 70);
    if (picked.isNotEmpty && mounted) {
      setState(() => _selectedImages = picked);
    }
  }

  // UPLOAD IMAGES
  Future<List<String>> _uploadImages() async {
    final List<String> urls = [];
    for (var img in _selectedImages) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(img.path)}';
      final ref = FirebaseStorage.instance.ref().child('comments/$productId/$fileName');
      await ref.putFile(File(img.path));
      final url = await ref.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  // POST COMMENT
  Future<void> _postComment() async {
    if (_currentUser == null || (_commentController.text.trim().isEmpty && _selectedImages.isEmpty)) {
      return;
    }

    setState(() {
      _isPostingComment = true;
      _uploading = true;
    });

    try {
      final userDoc = await firestore.collection('users').doc(_currentUser!.uid).get();
      final username = userDoc['username'] ?? 'Anonymous';

      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        imageUrls = await _uploadImages();
      }

      await firestore
          .collection('products')
          .doc(productId)
          .collection('comments')
          .add({
        'userId': _currentUser!.uid,
        'username': username,
        'comment': _commentController.text.trim(),
        'imageUrls': imageUrls,
        'likeCount': 0,
        'dislikeCount': 0,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _commentController.clear();
        _selectedImages.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment posted!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPostingComment = false;
          _uploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final name = product['name'] ?? 'Unnamed Product';
    final price = (product['price'] ?? 0).toDouble();
    final imageUrl = product['imageUrl'] ?? 'https://via.placeholder.com/300x300?text=No+Image';
    final description = product['description'] ?? 'No description available.';
    final brand = product['brand'] ?? 'Manny Gas';
    final category = product['category'] ?? 'LPG';
    final weight = product['weight'] ?? '11kg';
    final stock = product['stock'] ?? 0;
    final isAvailable = product['isAvailable'] ?? true;

    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2236),
        elevation: 0,
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      key: _imageKey,
                      margin: const EdgeInsets.all(16),
                      height: 260,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.contain),
                      ),
                    ),
                    if (!isAvailable)
                      Positioned(
                        top: 25,
                        left: 25,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                          child: const Text('Unavailable', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0D2236))),
                      const SizedBox(height: 8),
                      Text('₱${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                      const SizedBox(height: 10),

                      // LIVE RATING + STOCK
                      StreamBuilder<QuerySnapshot>(
                        stream: firestore.collection('products').doc(productId).collection('reviews').snapshots(),
                        builder: (context, snapshot) {
                          double liveRating = 0.0;
                          int reviewCount = 0;
                          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                            final reviews = snapshot.data!.docs;
                            reviewCount = reviews.length;
                            final total = reviews.fold<double>(0.0, (sum, doc) => sum + ((doc['rating'] ?? 0) as num).toDouble());
                            liveRating = reviewCount > 0 ? total / reviewCount : 0.0;
                          }
                          return Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 20),
                              const SizedBox(width: 4),
                              Text('${liveRating.toStringAsFixed(1)} ($reviewCount reviews)', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                              const SizedBox(width: 20),
                              Text(stock > 0 ? 'In Stock ($stock)' : 'Out of Stock', style: TextStyle(fontSize: 13, color: stock > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.w600)),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildInfoChip(Icons.local_gas_station, brand),
                          const SizedBox(width: 8),
                          _buildInfoChip(Icons.scale, weight),
                          const SizedBox(width: 8),
                          _buildInfoChip(Icons.category, category),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(thickness: 1, color: Colors.black12),
                      const SizedBox(height: 16),

                      const Text('Product Description', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0D2236))),
                      const SizedBox(height: 6),
                      Text(description, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4)),
                      const SizedBox(height: 20),

                      // USER REVIEWS (max 2)
                      const Text('User Reviews', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0D2236))),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot>(
                        stream: firestore.collection('products').doc(productId).collection('reviews').orderBy('createdAt', descending: true).limit(2).snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No reviews yet. Be the first to review!', style: TextStyle(color: Colors.black54, fontSize: 13)));
                          }
                          final reviews = snapshot.data!.docs;
                          final reviewWidgets = reviews.map<Widget>((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final userId = data['userId'] as String;
                            final rating = (data['rating'] ?? 0).toDouble();
                            final reviewText = data['review'] ?? '';
                            final timestamp = data['createdAt'] as Timestamp?;
                            final date = timestamp?.toDate();
                            final dateStr = date != null ? '${date.month}/${date.day}/${date.year}' : 'Just now';

                            return FutureBuilder<DocumentSnapshot>(
                              future: firestore.collection('users').doc(userId).get(),
                              builder: (context, userSnap) {
                                final username = userSnap.data?.get('username') ?? 'Anonymous';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Text(username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                                          Row(children: List.generate(5, (i) => Icon(i < rating.round() ? Icons.star : Icons.star_border, color: Colors.amber, size: 18))),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(reviewText, style: const TextStyle(fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                    ],
                                  ),
                                );
                              },
                            );
                          }).toList();

                          if (reviews.isNotEmpty) {
                            reviewWidgets.add(
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AllReviewsScreen(productId: productId))),
                                  child: const Text('See all reviews', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D2236))),
                                ),
                              ),
                            );
                          }
                          return Column(children: reviewWidgets);
                        },
                      ),
                      const SizedBox(height: 30),

                      // COMMENTS SECTION
                      const Text('Comments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0D2236))),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot>(
                        stream: firestore.collection('products').doc(productId).collection('comments').orderBy('timestamp', descending: true).limit(2).snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          final docs = snapshot.data!.docs;
                          if (docs.isEmpty) return const Text('No comments yet.', style: TextStyle(color: Colors.black54, fontSize: 13));
                          final commentWidgets = docs.map<Widget>((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final timestamp = data['timestamp'] as Timestamp?;
                            final date = timestamp?.toDate();
                            return _commentTile(
                              username: data['username'] ?? 'Anonymous',
                              comment: data['comment'] ?? '',
                              date: date != null ? '${date.month}/${date.day}/${date.year}' : 'Just now',
                            );
                          }).toList();

                          if (docs.length >= 2) {
                            commentWidgets.add(
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AllCommentsScreen(productId: productId))),
                                  child: const Text('See all comments', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D2236))),
                                ),
                              ),
                            );
                          }
                          return Column(children: commentWidgets);
                        },
                      ),

                      const SizedBox(height: 16),

                      // WRITE COMMENT
                      if (_currentUser != null) ...[
                        if (_selectedImages.isNotEmpty)
                          Container(
                            height: 100,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedImages.length,
                              itemBuilder: (c, i) => Stack(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    width: 100,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(image: FileImage(File(_selectedImages[i].path)), fit: BoxFit.cover),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedImages.removeAt(i)),
                                      child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: 'Write a comment...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.attach_file), onPressed: _pickImages),
                                _uploading
                                    ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                    : IconButton(icon: const Icon(Icons.send), onPressed: _postComment),
                              ],
                            ),
                          ),
                          maxLines: 4,
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        const Text('Sign in to comment.', style: TextStyle(color: Colors.black54)),
                        const SizedBox(height: 16),
                      ],

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // FIXED BUTTONS
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))]),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (!isAvailable || _isAddingToCart) ? null : () async {
                        if (!mounted) return;
                        setState(() => _isAddingToCart = true);
                        await WidgetsBinding.instance.endOfFrame;

                        try {
                          if (_scrollController.hasClients) {
                            await _scrollController.animateTo(20, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                            await _scrollController.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
                          }
                        } catch (e) {
                          debugPrint('Scroll failed: $e');
                        }

                        await Future.delayed(const Duration(milliseconds: 150));
                        await _cartService.addToCart(product);
                        if (mounted) await _animateAndPop(context, imageUrl);
                        if (mounted) setState(() => _isAddingToCart = false);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D2236), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: _isAddingToCart ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.add_shopping_cart),
                      label: Text(_isAddingToCart ? 'Adding...' : 'Add to Cart', style: const TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isAvailable ? () {
                        final productWithTotal = Map<String, dynamic>.from(product);
                        productWithTotal['quantity'] = 1;
                        productWithTotal['totalPrice'] = (productWithTotal['price'] ?? 0) * 1;
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CheckoutScreen(product: productWithTotal)));
                      } : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Buy Now', style: TextStyle(fontSize: 16, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Chip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.blueGrey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF0D2236))),
      ]),
      backgroundColor: Colors.blueGrey.withOpacity(0.1),
    );
  }

  Widget _commentTile({required String username, required String comment, required String date}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Color(0xFFF9F6FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0D2236))),
              Text(date, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 4),
          Text(comment, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }
}

// AnimatedImageToCart (unchanged)
class AnimatedImageToCart extends StatefulWidget {
  final Offset startPosition;
  final Offset endPosition;
  final String imageUrl;
  final Size imageSize;

  const AnimatedImageToCart({super.key, required this.startPosition, required this.endPosition, required this.imageUrl, required this.imageSize});

  @override
  State<AnimatedImageToCart> createState() => _AnimatedImageToCartState();
}

class _AnimatedImageToCartState extends State<AnimatedImageToCart> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _curve.value;
        final midX = (widget.startPosition.dx + widget.endPosition.dx) / 2;
        final midY = widget.startPosition.dy - 120;
        final dx = _quadBezier(widget.startPosition.dx, midX, widget.endPosition.dx, t);
        final dy = _quadBezier(widget.startPosition.dy, midY, widget.endPosition.dy, t);
        final scale = 1 - (t * 0.8);
        final opacity = 1 - (t * 0.9);

        return Positioned(
          left: dx,
          top: dy,
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Image.network(
                widget.imageUrl,
                height: widget.imageSize.height * 0.5,
                width: widget.imageSize.width * 0.5,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }

  double _quadBezier(double start, double control, double end, double t) {
    return (1 - t) * (1 - t) * start + 2 * (1 - t) * t * control + t * t * end;
  }
}