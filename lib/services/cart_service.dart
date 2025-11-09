import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CartService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Add product to Firestore cart
  Future<void> addToCart(Map<String, dynamic> product) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in.");

    final cartItemRef = _firestore
        .collection('cart')
        .doc(user.uid)
        .collection('items')
        .doc(product['id']);

    final doc = await cartItemRef.get();

    if (doc.exists) {
      // If already in cart → increment qty
      final currentQty = doc['qty'] ?? 1;
      await cartItemRef.update({'qty': currentQty + 1});
    } else {
      // If new → create new cart item
      await cartItemRef.set({
        'title': product['name'] ?? 'Unnamed Product',
        'price': product['price'] ?? 0,
        'qty': 1,
        'imageUrl': product['imageUrl'] ??
            'https://via.placeholder.com/300x300?text=No+Image',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Get all cart items for current user
  Stream<QuerySnapshot> getCartItemsStream() {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in.");
    return _firestore
        .collection('cart')
        .doc(user.uid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Update quantity
  Future<void> updateQty(String id, int qty) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in.");
    await _firestore
        .collection('cart')
        .doc(user.uid)
        .collection('items')
        .doc(id)
        .update({'qty': qty});
  }

  /// Remove item
  Future<void> removeItem(String id) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in.");
    await _firestore
        .collection('cart')
        .doc(user.uid)
        .collection('items')
        .doc(id)
        .delete();
  }

  /// Clear cart
  Future<void> clearCart() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in.");

    final cartItems =
        await _firestore.collection('cart').doc(user.uid).collection('items').get();

    for (final doc in cartItems.docs) {
      await doc.reference.delete();
    }
  }
}
