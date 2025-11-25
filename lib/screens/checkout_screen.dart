import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:daligas/screens/order_success_screen.dart';
import 'package:daligas/screens/manage_address_screen.dart';
import 'package:daligas/screens/purchases_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:daligas/screens/gcash_payment_screen.dart';
import 'package:daligas/services/firebase_functions.dart'; 
import 'package:daligas/main_mobile.dart';

class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic>? product;
  final List<Map<String, dynamic>>? selectedItems;

  const CheckoutScreen({Key? key, this.product, this.selectedItems}) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String fullName = 'Loading...';
  String contactNumber = '';
  String activeAddress = 'Getting address...';
  String _paymentMethod = 'cod';
  bool _isPlacingOrder = false;
  bool _hasShownGcashInfo = false; // Prevents spam dialog

  final user = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = firestore;

  late final List<Map<String, dynamic>> checkoutItems;

  @override
  void initState() {
    super.initState();
    checkoutItems = widget.product != null
        ? [widget.product!]
        : widget.selectedItems ?? [];

    _fetchUserDetails();
  }

  Future<void> _fetchUserDetails() async {
    if (user == null || !mounted) return;

    try {
      final userDoc = await firestore.collection('users').doc(user!.uid).get();
      if (!userDoc.exists) {
        if (mounted) {
          setState(() {
            fullName = 'Unknown User';
            contactNumber = 'No contact';
            activeAddress = 'No address found';
          });
        }
        return;
      }

      final data = userDoc.data() ?? {};
      final name = (data['fullName'] ?? data['name'] ?? user!.displayName ?? '').toString();
      final phone = (data['phone'] ?? user!.phoneNumber ?? '').toString();

      String? selectedAddressString;
      final rawAddresses = data['addresses'];
      if (rawAddresses != null) {
        final List<Map<String, dynamic>> addressList = [];

        if (rawAddresses is List) {
          for (final item in rawAddresses) {
            if (item is Map) addressList.add(Map<String, dynamic>.from(item));
          }
        } else if (rawAddresses is Map) {
          for (final entry in rawAddresses.entries) {
            final val = entry.value;
            if (val is Map) addressList.add(Map<String, dynamic>.from(val));
          }
        }

        if (addressList.isNotEmpty) {
          Map<String, dynamic>? activeMap;
          try {
            activeMap = addressList.firstWhere((a) {
              final v = a['isActive'];
              return (v is bool && v) || (v is String && v.toLowerCase() == 'true');
            });
          } catch (_) {
            activeMap = addressList.first;
          }
          selectedAddressString = _formatAddressMap(activeMap);
        }
      }

      if (mounted) {
        setState(() {
          fullName = name.isNotEmpty ? name : 'User';
          contactNumber = phone.isNotEmpty ? phone : 'No contact';
          activeAddress = selectedAddressString ?? 'No active address found';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          fullName = user!.displayName ?? 'User';
          contactNumber = user!.phoneNumber ?? '';
          activeAddress = 'Failed to load address';
        });
      }
    }
  }

  String _formatAddressMap(Map<String, dynamic> a) {
    if (a['fullAddress']?.toString().trim().isNotEmpty == true) {
      return a['fullAddress'];
    }

    final parts = <String>[];
    final fields = ['street', 'barangay', 'city', 'province', 'postal', 'postalCode'];
    for (final field in fields) {
      final val = a[field]?.toString().trim();
      if (val != null && val.isNotEmpty) parts.add(val);
    }
    return parts.join(', ');
  }

  Future<void> _changeAddress() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageAddressScreen()));
    await _fetchUserDetails();
  }

  double get totalPrice {
    return checkoutItems.fold(0.0, (sum, item) {
      final price = (item['price'] ?? 0).toDouble();
      final qty = (item['quantity'] ?? 1) as int;
      return sum + (price * qty);
    });
  }

  Future<void> _clearCart() async {
    if (user == null) return;
    final batch = firestore.batch();
    final cartItems = await firestore.collection('cart').doc(user!.uid).collection('items').get();

    for (var doc in cartItems.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

@override
  Widget build(BuildContext context) {
    const Color darkBlue = Color(0xFF001B33);
    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Checkout', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAddressCard(),
            const SizedBox(height: 12),
            _buildProductList(),
            const SizedBox(height: 12),
            _buildPaymentMethods(),
            const SizedBox(height: 12),
            _buildPaymentDetails(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildAddressCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.location_on, color: Colors.redAccent),
        title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$contactNumber\n$activeAddress', style: const TextStyle(height: 1.4)),
        trailing: TextButton(onPressed: _changeAddress, child: const Text('Change', style: TextStyle(color: Colors.blueAccent))),
      ),
    );
  }

  Widget _buildProductList() {
    if (checkoutItems.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No items to checkout.', style: TextStyle(color: Colors.grey))));
    }

    return Column(
      children: checkoutItems.map((item) {
        final name = item['name'] ?? 'Unknown';
        final price = (item['price'] ?? 0).toDouble();
        final qty = (item['quantity'] ?? 1) as int;

        final nameLower = name.toLowerCase();
        final match = RegExp(r'(\d+)\s*kg').firstMatch(nameLower);
        final weight = match != null ? double.tryParse(match.group(1)!) ?? 0 : 0;
        final perKg = weight > 0 ? price / weight : 0;
        final subtotal = price * qty;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    item['imageUrl'] ?? '',
                    width: 70, height: 70, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(width: 70, height: 70, color: Colors.grey[300], child: const Icon(Icons.image_not_supported, color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      if (weight > 0) ...[
                        Text('₱${price.toStringAsFixed(2)} / ${weight}kg'),
                        Text('₱${perKg.toStringAsFixed(2)} per kg'),
                      ] else
                        Text('₱${price.toStringAsFixed(2)} (weight not found)'),
                      Text('Qty: $qty'),
                    ],
                  ),
                ),
                Text('₱${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

Widget _buildPaymentMethods() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),

          // Cash on Delivery
          RadioListTile<String>(
            title: const Text('Cash on Delivery (COD)'),
            subtitle: const Text('Pay when your order arrives', style: TextStyle(fontSize: 13)),
            secondary: const Icon(Icons.local_shipping, color: Colors.orange),
            value: 'cod',
            groupValue: _paymentMethod,
            onChanged: (v) => setState(() {
              _paymentMethod = v!;
              _hasShownGcashInfo = false;
            }),
          ),

          // GCash — Super Friendly Version
          RadioListTile<String>(
            title: const Text('GCash'),
            subtitle: const Text('Fast & instant payment', style: TextStyle(fontSize: 13, color: Colors.green)),
            secondary: Image.asset('assets/images/gcash.png', width: 44),
            value: 'ewallet',
            groupValue: _paymentMethod,
            onChanged: (v) async {
              if (_paymentMethod == 'ewallet') return;

              final confirm = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 28),
                      SizedBox(width: 12),
                      Expanded(child: Text('Just so you know!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                    ],
                  ),
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 60),
                      SizedBox(height: 16),
                      Text(
                        'GCash payments are instant and final.\n\n'
                        'This helps us prepare and deliver your order faster!\n\n'
                        'Once paid, the order cannot be cancelled — but don’t worry, we’ve got you covered with great service',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, height: 1.6),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>  Navigator.pop(context, false),
                      child: const Text('I’ll use COD instead'),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.payment, color: Colors.white),
                      label: const Text('Pay with GCash'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                setState(() {
                  _paymentMethod = v!;
                  _hasShownGcashInfo = true;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Order Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...checkoutItems.map((item) {
              final name = item['name'] ?? 'Unknown';
              final qty = (item['quantity'] ?? item['qty'] ?? 1) as int;
              final price = (item['price'] ?? 0).toDouble();
              final subtotal = price * qty;

              final nameLower = name.toLowerCase();
              final match = RegExp(r'(\d+)\s*kg').firstMatch(nameLower);
              final weight = match != null ? '${match.group(1)}kg' : '';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$name $weight x$qty'),
                    Text('₱${subtotal.toStringAsFixed(2)}'),
                  ],
                ),
              );
            }),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('₱${totalPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('₱${totalPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.red)),
              ],

            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isPlacingOrder ? Colors.grey : Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _isPlacingOrder ? null : _placeOrder,
              child: _isPlacingOrder
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Place Order', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

Future<void> _placeOrder() async {
  if (user == null) {
    _showSnackBar('Please log in to place an order.');
    return;
  }
  if (checkoutItems.isEmpty) {
    _showSnackBar('Your cart is empty.');
    return;
  }
  if (activeAddress.contains('No active') || activeAddress.contains('Failed')) {
    _showSnackBar('Please set a valid delivery address.');
    return;
  }

  setState(() => _isPlacingOrder = true);

  try {
    // FIX: Use the global 'functions' instance from main_mobile.dart
    if (_paymentMethod == 'cod') {
      final callable = functions.httpsCallable('createOrder'); // ← NOW GOES TO SINGAPORE
      final result = await callable({
        'userId': user!.uid,
        'items': checkoutItems.map((i) => {
          'productId': i['id'],
          'name': i['name'],
          'price': i['price'],
          'quantity': i['quantity'],
          'imageUrl': i['imageUrl'],
        }).toList(),
        'paymentMethod': 'cod',
        'deliveryAddress': activeAddress,
      });

      final orderId = result.data['orderId'] as String;
      await _clearCart();

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => OrderSuccessScreen(orderId: orderId)),
          (route) => false,
        );
      }
    }
    else if (_paymentMethod == 'ewallet') {
      final callable = functions.httpsCallable('createPaymongoPayment'); // ← NOW WORKS!
      final result = await callable({
        'userId': user!.uid,
        'items': checkoutItems.map((i) => {
          'productId': i['id'],
          'name': i['name'],
          'price': i['price'],
          'quantity': i['quantity'],
          'imageUrl': i['imageUrl'],
        }).toList(),
        'deliveryAddress': activeAddress,
      });

      final redirectUrl = result.data['redirectUrl'] as String;
      final orderId = result.data['orderId'] as String;

      await _clearCart();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GcashPaymentScreen(
              paymentUrl: redirectUrl,
              orderAmount: '₱${totalPrice.toStringAsFixed(2)}',
              pendingOrderId: orderId,
            ),
          ),
        );
      }
    }
  } catch (e) {
    print('Full error: $e'); // ← Add this for debugging
    _showSnackBar('Order failed: ${e.toString()}');
  } finally {
    if (mounted) setState(() => _isPlacingOrder = false);
  }
}

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
    );
  }
}