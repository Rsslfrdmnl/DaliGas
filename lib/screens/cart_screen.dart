import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/screens/checkout_screen.dart';
import 'package:daligas/main_mobile.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with SingleTickerProviderStateMixin {
  bool editMode = false;
  bool selectAll = false;
  User? user;
  final FirebaseFirestore _firestore = firestore;
  Stream<QuerySnapshot>? _cartStream;
  Set<String> selectedIds = {};
  Set<String> deletingIds = {};

  late AnimationController _snapController;
  StreamSubscription<User?>? _authSubscription; // ← ADD

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _initUserAndStream();
  }

  @override
  void dispose() {
    _authSubscription?.cancel(); // ← ADD
    _snapController.dispose();
    super.dispose();
  }

  Future<void> _initUserAndStream() async {
    user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      _updateCartStream(user!.uid);
    }

    // Listen for auth changes
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((u) {
      if (!mounted) return;
      setState(() {
        user = u;
        if (u != null) {
          _updateCartStream(u.uid);
        } else {
          _cartStream = null;
        }
      });
    });
  }

  void _updateCartStream(String uid) {
    _cartStream = firestore.collection('cart').doc(uid).collection('items').snapshots();
    if (mounted) setState(() {});
  }

  Future<void> updateQuantity(String id, int qty) async {
    if (user == null) return;
    await firestore
        .collection('cart')
        .doc(user!.uid)
        .collection('items')
        .doc(id)
        .update({'qty': qty});
  }

  Future<void> _deleteSelectedItems(List<String> ids) async {
    if (user == null) return;
    final batch = firestore.batch();
    for (final id in ids) {
      final ref = firestore.collection('cart').doc(user!.uid).collection('items').doc(id);
      batch.delete(ref);
    }
    await batch.commit();
  }

  void _confirmDelete(List<String> ids) async {
    if (ids.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D2236),
        title: const Text('Delete Items', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete the selected items?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel', style: TextStyle(color: Colors.white))),
          TextButton(onPressed: () => Navigator.pop(_, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        deletingIds.addAll(ids);
        selectedIds.clear();
        selectAll = false;
      });

      _snapController.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 400));
      await _deleteSelectedItems(ids);

      if (mounted) {
        setState(() => deletingIds.removeAll(ids));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2236),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  const Expanded(
                    child: Text('Cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20), textAlign: TextAlign.center),
                  ),
                  TextButton(
                    onPressed: () => setState(() => editMode = !editMode),
                    child: Text(editMode ? 'Done' : 'Edit', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white, height: 1),

            // Cart Items
            Expanded(
              child: _cartStream == null
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : StreamBuilder<QuerySnapshot>(
                      stream: _cartStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text('No items in cart', style: TextStyle(color: Colors.white)));
                        }

                        final items = snapshot.data!.docs;
                        double total = 0;
                        int totalQty = 0;
                        for (var doc in items) {
                          final data = doc.data() as Map<String, dynamic>;
                          if (selectedIds.contains(doc.id)) {
                            final price = (data['price'] ?? 0).toDouble();
                            final qty = (data['qty'] ?? 1) as int;
                            total += price * qty;
                            totalQty += qty;
                          }
                        }

                        return Column(
                          children: [
                            // Select All
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: selectAll,
                                        onChanged: (value) {
                                          setState(() {
                                            selectAll = value ?? false;
                                            selectedIds = selectAll ? items.map((e) => e.id).toSet() : {};
                                          });
                                        },
                                        activeColor: null,
                                        checkColor: Colors.black,
                                      ),
                                      const Text('Select All', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                  if (editMode) Text('Selected: ${selectedIds.length}', style: const TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),

                            // Cart List
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 14),
                                itemBuilder: (context, index) {
                                  final doc = items[index];
                                  final data = doc.data() as Map<String, dynamic>;
                                  final isSelected = selectedIds.contains(doc.id);
                                  final isDeleting = deletingIds.contains(doc.id);

                                  return FadeTransition(
                                    opacity: Tween<double>(begin: 1.0, end: isDeleting ? 0.0 : 1.0).animate(
                                      CurvedAnimation(parent: _snapController, curve: Curves.easeOutExpo),
                                    ),
                                    child: Transform.scale(
                                      scale: isDeleting ? (1 - _snapController.value * 0.4) : 1.0,
                                      child: _CartTile(
                                        key: ValueKey(doc.id),
                                        id: doc.id,
                                        title: data['title'] ?? 'Unnamed Product',
                                        price: (data['price'] ?? 0).toDouble(),
                                        qty: data['qty'] ?? 1,
                                        imageUrl: data['imageUrl'] ?? '',
                                        selected: isSelected,
                                        onSelected: isDeleting ? null : () {
                                          setState(() {
                                            isSelected ? selectedIds.remove(doc.id) : selectedIds.add(doc.id);
                                          });
                                        },
                                        onIncrement: () => updateQuantity(doc.id, (data['qty'] ?? 1) + 1),
                                        onDecrement: () {
                                          if ((data['qty'] ?? 1) > 1) {
                                            updateQuantity(doc.id, (data['qty'] ?? 1) - 1);
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                            // Bottom Bar
                            Container(
                              color: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: editMode
                                  ? Row(
                                      children: [
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                          onPressed: selectedIds.isEmpty ? null : () => _confirmDelete(selectedIds.toList()),
                                          icon: const Icon(Icons.delete),
                                          label: const Text('Delete Selected'),
                                        ),
                                        const Spacer(),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        const Text('Total:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                                        const SizedBox(width: 8),
                                        Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
                                        const Spacer(),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0D2236),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          ),
                                          onPressed: selectedIds.isEmpty
                                              ? null
                                              : () {
                                                  final selectedDocs = items.where((doc) => selectedIds.contains(doc.id)).map((doc) {
                                                    final data = doc.data() as Map<String, dynamic>;
                                                    return {
                                                      'id': doc.id,
                                                      'name': data['title'] ?? '', // ← FIXED: 'name' for CheckoutScreen
                                                      'price': data['price'] ?? 0,
                                                      'quantity': data['qty'] ?? 1,
                                                      'imageUrl': data['imageUrl'] ?? '',
                                                    };
                                                  }).toList();

                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(builder: (_) => CheckoutScreen(selectedItems: selectedDocs)),
                                                  );
                                                },
                                          child: Text('Check Out ($totalQty)'),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
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

// Cart Tile
class _CartTile extends StatelessWidget {
  final String id;
  final String title;
  final double price;
  final int qty;
  final String imageUrl;
  final bool selected;
  final VoidCallback? onSelected;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _CartTile({
    super.key,
    required this.id,
    required this.title,
    required this.price,
    required this.qty,
    required this.imageUrl,
    required this.selected,
    required this.onSelected,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final total = price * qty;
    return GestureDetector(
      onTap: onSelected,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? Colors.lightBlue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? Colors.blueAccent : Colors.transparent, width: 1.5),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? Colors.blueAccent : Colors.grey),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 80, height: 80, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200, width: 80, height: 80),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, color: Colors.black, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(icon: const Icon(Icons.remove, size: 20), onPressed: onDecrement),
                Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.add, size: 20), onPressed: onIncrement),
              ],
            ),
          ],
        ),
      ),
    );
  }
}