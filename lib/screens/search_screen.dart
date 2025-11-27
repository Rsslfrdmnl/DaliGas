import 'dart:async'; // ← ADD
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/screens/product_detail_screen.dart';
import 'package:daligas/main_mobile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int tappedIndex = -1;

  // ── DEBOUNCE SEARCH ─────────────────────
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      body: SafeArea(
        child: Column(
          children: [
            // === SEARCH BAR ===
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.black87, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Search here...',
                          hintStyle: const TextStyle(color: Colors.black54, fontSize: 15),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        ),
                        // onChanged removed — using listener
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Divider(height: 1, thickness: 1, color: Colors.white),
            ),

            // === SEARCH RESULTS ===
            Expanded(
              child: _searchQuery.isEmpty
                  ? const Center(
                      child: Text(
                        'Type to search products...',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: firestore.collection('products').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text('No products found', style: TextStyle(color: Colors.white70)));
                        }

                        final filteredProducts = snapshot.data!.docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final name = (data['name'] ?? '').toString().toLowerCase();
                          return name.contains(_searchQuery);
                        }).toList();

                        if (filteredProducts.isEmpty) {
                          return const Center(child: Text('No results found', style: TextStyle(color: Colors.white70)));
                        }

                        return GridView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredProducts.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.8,
                          ),
                          itemBuilder: (context, index) {
                            final doc = filteredProducts[index];
                            final product = doc.data() as Map<String, dynamic>;
                            final name = product['name'] ?? 'Unnamed';
                            final price = product['price'] ?? 0;
                            final imageUrl = product['imageUrl'] ?? 'https://via.placeholder.com/300';

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
                                        'id': doc.id,
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
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeOut,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF173B5F), Color(0xFF1E4975)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: tappedIndex == index
                                                ? Colors.black.withOpacity(0.3)
                                                : Colors.black.withOpacity(0.4),
                                            blurRadius: tappedIndex == index ? 6 : 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
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
                                                child: Image.network(
                                                  imageUrl,
                                                  fit: BoxFit.contain,
                                                  width: double.infinity,
                                                  errorBuilder: (_, __, ___) => const Center(
                                                    child: Icon(Icons.image_not_supported, color: Colors.white, size: 40),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '₱${price.toStringAsFixed(2)}',
                                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1ED2AF)),
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(Icons.star, color: Colors.amber, size: 16),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      '${(product['rating'] ?? 4.0).toStringAsFixed(1)}',
                                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Text(
                                                      'Stocks: ${(product['stock'] ?? 0)}',
                                                      style: TextStyle(
                                                        color: (product['stock'] ?? 0) > 0 ? Colors.white70 : Colors.redAccent,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
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
        ),
      ),
    );
  }
}