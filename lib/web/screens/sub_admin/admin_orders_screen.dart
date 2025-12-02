import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'package:daligas/web/main_web.dart';
import 'package:flutter/services.dart'; // Add this import for Clipboard functionality
import 'package:csv/csv.dart'; // Add this to pubspec.yaml: csv: ^5.0.2
import 'dart:typed_data';
import 'dart:html' as html; // For web file download
import 'admin_dashboard_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_feedbacks_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_screen.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  String searchQuery = '';
  String selectedDateRange = 'All Time';
  String selectedStatus = 'All';
  int currentPage = 0;
  final int itemsPerPage = 6;
  final TextEditingController searchController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String _selectedPaymentMethod = 'cod';
  final List<Map<String, dynamic>> _manualCart = [];

  void _showManualOrderDialog() {
    _customerNameController.clear();
    _customerPhoneController.clear();
    _addressController.clear();
    _selectedPaymentMethod = 'cod';
    _manualCart.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Walk In Order"),
          content: SizedBox(
            width: 600,
            height: 680,
            child: Column(
              children: [
                // Customer Info
                TextField(
                  controller: _customerNameController,
                  decoration: const InputDecoration(
                    labelText: "Customer Name",
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customerPhoneController,
                  decoration: const InputDecoration(
                    labelText: "Phone (optional)",
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: "Delivery Address",
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Payment Method
                DropdownButtonFormField<String>(
                  value: _selectedPaymentMethod,
                  decoration: const InputDecoration(labelText: "Payment Method"),
                  items: const [
                    DropdownMenuItem(value: 'cod', child: Text("Cash on Delivery")),
                    DropdownMenuItem(value: 'gcash', child: Text("GCash (Paid)")),
                  ],
                  onChanged: (v) => setDialogState(() => _selectedPaymentMethod = v!),
                ),
                const SizedBox(height: 20),

                // Products List
                const Text("Add Products", style: TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('products').where('isAvailable', isEqualTo: true).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                      final products = snapshot.data!.docs;
                      return ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, i) {
                          final doc = products[i];
                          final data = doc.data() as Map<String, dynamic>;
                          final name = data['name'] ?? 'No Name';
                          final price = (data['price'] ?? 0).toDouble();
                          final stock = data['stock'] ?? 0;
                          final imageUrl = data['imageUrl'] ?? '';

                          final existing = _manualCart.cast<Map<String, dynamic>?>().firstWhere(
                            (e) => e?['productId'] == doc.id,
                            orElse: () => null,
                          );

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  if (imageUrl.isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(imageUrl, width: 60, height: 60, fit: BoxFit.contain),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text("₱${price.toStringAsFixed(2)} • Stock: $stock"),
                                      ],
                                    ),
                                  ),
                                  if (existing != null) ...[
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                                          onPressed: stock > 0
                                              ? () => setDialogState(() {
                                                    existing['quantity']--;
                                                    if (existing['quantity'] <= 0) _manualCart.remove(existing);
                                                  })
                                              : null,
                                        ),
                                        Text("${existing['quantity']}", style: const TextStyle(fontSize: 18)),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle, color: Colors.green),
                                          onPressed: stock > existing['quantity']
                                              ? () => setDialogState(() => existing['quantity']++)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ] else
                                    ElevatedButton(
                                      onPressed: stock > 0
                                          ? () => setDialogState(() {
                                                _manualCart.add({
                                                  'productId': doc.id,
                                                  'name': name,
                                                  'price': price,
                                                  'quantity': 1,
                                                  'imageUrl': imageUrl,
                                                });
                                              })
                                          : null,
                                      child: const Text(
                                        "Add",
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

                // Cart Summary
                if (_manualCart.isNotEmpty) ...[
                  const Divider(),
                  ..._manualCart.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("${item['name']} × ${item['quantity']}"),
                            Text("₱${(item['price'] * item['quantity']).toStringAsFixed(2)}"),
                          ],
                        ),
                      )),
                  const Divider(),
                  Text(
                    "Total: ₱${_manualCart.fold(0.0, (sum, i) => sum + i['price'] * i['quantity']).toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: _manualCart.isEmpty ||
                      _customerNameController.text.trim().isEmpty ||
                      _addressController.text.trim().isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _createManualOrder();
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("Create Order"),
            ),
          ],
        ),
      ),
    );
  }

  void _exportToCsv() async {
  try {
    final snapshot = await firestore.collection('orders').get();
    List<List<dynamic>> csvData = [];

    // Add header row
    csvData.add([
      'Order ID',
      'Customer Name',
      'Date & Time',
      'Total Amount',
      'Payment Method',
      'Delivery Status',
      'Items Count'
    ]);

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final userId = data['userId'] as String?;
      String customerName = 'Unknown User';
      
      if (userId != null && userId.isNotEmpty) {
        try {
          final userDoc = await firestore.collection('users').doc(userId).get();
          if (userDoc.exists) {
            customerName = (userDoc.data() as Map<String, dynamic>?)?['fullName']?.toString() ?? 'Unknown User';
          }
        } catch (e) {
          customerName = 'Error retrieving user';
        }
      }

      final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final total = (data['total'] ?? 0).toDouble();
      final paymentMethod = data['paymentMethod'] ?? 'COD';
      final status = data['deliveryStatus'] ?? 'Processing';
      final itemsCount = (data['items'] as List<dynamic>?)?.length ?? 0;

      csvData.add([
        doc.id,
        customerName,
        DateFormat('MMMM d, yyyy - hh:mm a').format(createdAt),
        total.toStringAsFixed(2),
        paymentMethod.toUpperCase(),
        status,
        itemsCount.toString(),
      ]);
    }

    // Convert to CSV string
    String csvString = const ListToCsvConverter().convert(csvData);
    
    // Create and download file
    final blob = html.Blob([csvString]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'orders_export_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.csv')
      ..click();
    
    html.Url.revokeObjectUrl(url);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Orders exported successfully as CSV')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error exporting orders: $e')),
    );
  }
}

  Future<void> _logout(BuildContext context) async {
  await FirebaseAuth.instance.signOut();

  if (!context.mounted) {
    return;
  }

  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
}

Future<void> _createManualOrder() async {

    final items = _manualCart.map((i) => {
          'productId': i['productId'],
          'name': i['name'],
          'price': i['price'],
          'quantity': i['quantity'],
          'imageUrl': i['imageUrl'] ?? '',
        }).toList();

    try {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
    final result = await functions.httpsCallable('createOrder').call({
      // 'userId': userId,                     // ← REMOVE THIS LINE
      'items': items,
      'paymentMethod': _selectedPaymentMethod,
      'deliveryAddress': _addressController.text.trim(),
      // Directly pass customer info for manual orders
      'customerName': _customerNameController.text.trim(),
      'customerPhone': _customerPhoneController.text.trim().isNotEmpty
          ? _customerPhoneController.text.trim()
          : null,
      // Optional flag so your Cloud Function knows it's a manual order
      'isManualOrder': true,
    });

      if (result.data['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Manual order created! #${result.data['orderId'].toString().substring(0, 8)}"),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {}); // refresh list
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Failed to create order: $e"), backgroundColor: Colors.red),
    );
  }
}

  // Your original sidebar – 100% unchanged
  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 220,
      color: const Color(0xFF0D2236),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.translate(
                offset: const Offset(-10, 0),
                child: Image.asset("assets/images/daligas_logo.png", height: 80),
              ),
              Transform.translate(
                offset: const Offset(-22, 0),
                child: const Text(
                  "DALI GAS",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          _SidebarItem(Icons.dashboard, "Dashboard", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminDashboardScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.shopping_cart, "Orders", true, () {}),
          _SidebarItem(Icons.inventory, "Inventory", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminInventoryScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.local_shipping, "Delivery Management", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminDeliveryScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.feedback, "Feedback", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminFeedbackScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.flag, "User Reports", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminReportsScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.settings, "Settings", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminSettingsScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),

          const Spacer(),
          _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Your original stat card – unchanged
  Widget _buildStatCard(String value, String label) {
    return Expanded(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  void _updateStatus(String orderId, String newStatus) async {
    await firestore.collection('orders').doc(orderId).update({
      'deliveryStatus': newStatus,
      if (newStatus == 'Delivered') 'deliveredAt': FieldValue.serverTimestamp(),
    });
  }

  void _showOrderDetailsDialog(QueryDocumentSnapshot orderDoc) {
    final data = orderDoc.data() as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final total = (data['total'] ?? 0).toDouble();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Order #${orderDoc.id.substring(0, 8).toUpperCase()}"),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...items.map((item) {
                final name = item['name']?.toString() ?? 'Unknown Item';
                final qty = (item['quantity'] ?? 0).toInt();
                final price = (item['price'] ?? 0).toDouble();
                final imageUrl = item['imageUrl'] as String?;

                return ListTile(
                  leading: imageUrl != null && imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(imageUrl, width: 50, height: 50, fit: BoxFit.contain),
                        )
                      : Container(width: 50, height: 50, color: Colors.grey[300], child: const Icon(Icons.image)),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text("$qty × ₱${price.toStringAsFixed(2)}"),
                  trailing: Text("₱${(qty * price).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }),
              const Divider(height: 30),
              Align(
                alignment: Alignment.centerRight,
                child: Text("Total: ₱${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    // Remove floatingActionButton completely
    // We'll place the button inside the layout instead

    body: Row(
      children: [
        _buildSidebar(context),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Title + Create Manual Order Button (Top Right)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Orders",
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    // Green "Create Manual Order" button – now in top-right
                    FloatingActionButton.extended(
                      onPressed: _showManualOrderDialog,
                      backgroundColor: Colors.green,
                      icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
                      label: const Text(
                        "Walk In Order",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      elevation: 6,
                      heroTag: "createManualOrder", // avoids conflict if you add more FABs later
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                  // Live Stats – same as before
                  StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('orders').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Row(
                          children: [
                            _buildStatCard("...", "New Orders Today"),
                            const SizedBox(width: 16),
                            _buildStatCard("...", "Pending Deliveries"),
                            const SizedBox(width: 16),
                            _buildStatCard("...", "Completed Orders"),
                            const SizedBox(width: 16),
                            _buildStatCard("...", "Cancelled Orders"),
                          ],
                        );
                      }

                      final docs = snapshot.data!.docs;
                      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

                      int newToday = 0, pending = 0, completed = 0, cancelled = 0;
                      for (var doc in docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                        final status = data['deliveryStatus'] ?? 'Processing';

                        if (createdAt != null && createdAt.isAfter(today.subtract(const Duration(days: 1)))) newToday++;
                        if (status == 'Processing' || status == 'Shipped') pending++;
                        if (status == 'Delivered') completed++;
                        if (status == 'Cancelled') cancelled++;
                      }

                      return Row(
                        children: [
                          _buildStatCard(newToday.toString(), "New Orders Today"),
                          const SizedBox(width: 16),
                          _buildStatCard(pending.toString(), "Pending Deliveries"),
                          const SizedBox(width: 16),
                          _buildStatCard(completed.toString(), "Completed Orders"),
                          const SizedBox(width: 16),
                          _buildStatCard(cancelled.toString(), "Cancelled Orders"),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Main card – your exact original layout
                  Expanded(
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Filters – now fully working
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: searchController,
                                      onChanged: (val) => setState(() {
                                        searchQuery = val.toLowerCase();
                                        currentPage = 0;
                                      }),
                                      decoration: InputDecoration(
                                        hintText: "Search by name/order ID",
                                        prefixIcon: const Icon(Icons.search),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 180,
                                    child: DropdownButtonFormField<String>(
                                      value: selectedDateRange,
                                      items: ['All Time', 'Today', 'This Week', 'This Month']
                                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                          .toList(),
                                      onChanged: (val) => setState(() {
                                        selectedDateRange = val!;
                                        currentPage = 0;
                                      }),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 160,
                                    child: DropdownButtonFormField<String>(
                                      value: selectedStatus,
                                      items: ['All', 'Processing', 'Shipped', 'Delivered', 'Cancelled']
                                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                          .toList(),
                                      onChanged: (val) => setState(() {
                                        selectedStatus = val!;
                                        currentPage = 0;
                                      }),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Orders Table with pagination
                            Expanded(
                              child: StreamBuilder<QuerySnapshot>(
                                stream: firestore.collection('orders').orderBy('createdAt', descending: true).snapshots(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) {
                                    return const Center(child: CircularProgressIndicator());
                                  }

                                  var filtered = snapshot.data!.docs.where((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    final status = data['deliveryStatus'] ?? 'Processing';
                                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                                    final orderId = doc.id.toLowerCase();
                                    final userId = data['userId'] as String?;
                                    final items = data['items'] as List<dynamic>? ?? [];

                                    // Search in: Order ID + Customer Name + Any Product Name
                                    final searchableText = [
                                      orderId,
                                      (userId ?? ''),
                                      ...items.map((item) => (item['name'] as String?)?.toLowerCase() ?? ''),
                                    ].join(' ');

                                    if (selectedStatus != 'All' && status != selectedStatus) return false;
                                    if (searchQuery.isNotEmpty && !searchableText.contains(searchQuery)) return false;

                                    final now = DateTime.now();
                                    if (selectedDateRange == 'Today') {
                                      final today = DateTime(now.year, now.month, now.day);
                                      if (!createdAt.isAfter(today.subtract(const Duration(days: 1)))) return false;
                                    } else if (selectedDateRange == 'This Week') {
                                      if (createdAt.isBefore(now.subtract(const Duration(days: 7)))) return false;
                                    } else if (selectedDateRange == 'This Month') {
                                      if (createdAt.month != now.month || createdAt.year != now.year) return false;
                                    }
                                    return true;
                                  }).toList();

                                  final totalPages = (filtered.length / itemsPerPage).ceil();
                                  final start = currentPage * itemsPerPage;
                                  final pageItems = filtered.length > start
                                      ? filtered.sublist(start, (start + itemsPerPage).clamp(0, filtered.length))
                                      : <QueryDocumentSnapshot>[];

                                  return Column(
                                    children: [
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: Container(
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.grey.shade300),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: DataTable(
                                              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                              dataRowHeight: 55,
                                              headingRowHeight: 50,
                                              horizontalMargin: 16,
                                              columnSpacing: 32,
                                              border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1)),
                                              columns: const [
                                                DataColumn(label: Text("Date & Time", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Customer", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Order Details", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Payment", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Action", style: TextStyle(fontWeight: FontWeight.w600))),
                                              ],
                                              rows: pageItems.map((doc) {
                                                final data = doc.data() as Map<String, dynamic>;
                                                final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                                                final status = data['deliveryStatus'] ?? 'Processing';
                                                final paymentMethod = (data['paymentMethod'] as String? ?? 'COD').toUpperCase();
                                                final userId = data['userId'] as String?;

                                                return DataRow(
                                                  cells: [
                                                    DataCell(Text(DateFormat('MMMM d, yyyy - hh:mm a').format(createdAt))),
                                                    DataCell(
  FutureBuilder<String>(
    future: () async {
      final data = doc.data() as Map<String, dynamic>;

      // 1. Prefer manually entered name (from manual orders)
      if (data.containsKey('customerName') && 
          data['customerName'] != null && 
          data['customerName'].toString().trim().isNotEmpty) {
        return data['customerName'].toString().trim();
      }

      // 2. Fallback: if there's a userId, fetch from users collection
      final userId = data['userId'] as String?;
      if (userId != null && userId.isNotEmpty) {
        try {
          final userDoc = await firestore.collection('users').doc(userId).get();
          if (userDoc.exists) {
            return (userDoc.data()?['fullName']?.toString() ?? 'Unknown User');
          }
        } catch (_) {}
      }

      return 'Guest / Manual Order';
    }(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Text("...");
      }
      return Text(snapshot.data ?? 'Unknown');
    },
  ),
),
                                                    DataCell(
                                                      MouseRegion(
                                                        cursor: SystemMouseCursors.click, // Ensures click cursor on hover
                                                        child: GestureDetector(
                                                          onTap: () => _showOrderDetailsDialog(doc),
                                                          child: const Text(
                                                            "See Details",
                                                            style: TextStyle(
                                                              color: Colors.blue, 
                                                              decoration: TextDecoration.underline, 
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(Text(paymentMethod)),
                                                    DataCell(
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: status == 'Delivered'
                                                              ? Colors.green.shade50
                                                              : status == 'Cancelled'
                                                                  ? Colors.red.shade50
                                                                  : status == 'Shipped'
                                                                      ? Colors.blue.shade50
                                                                      : Colors.orange.shade50,
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(
                                                          status,
                                                          style: TextStyle(
                                                            color: status == 'Delivered'
                                                                ? Colors.green
                                                                : status == 'Cancelled'
                                                                    ? Colors.red
                                                                    : status == 'Shipped'
                                                                        ? Colors.blue
                                                                        : Colors.orange,
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          if (status == 'Processing')
                                                            OutlinedButton(
                                                              onPressed: () => _updateStatus(doc.id, 'Shipped'),
                                                              style: OutlinedButton.styleFrom(
                                                                foregroundColor: Colors.blue,
                                                                backgroundColor: Colors.blue.shade50,
                                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                              ),
                                                              child: const Text("Ship", style: TextStyle(fontWeight: FontWeight.w600)),
                                                            )
                                                          else if (status == 'Shipped')
                                                            OutlinedButton(
                                                              onPressed: () => _updateStatus(doc.id, 'Delivered'),
                                                              style: OutlinedButton.styleFrom(
                                                                foregroundColor: Colors.green,
                                                                backgroundColor: Colors.green.shade50,
                                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                              ),
                                                              child: const Text("Complete", style: TextStyle(fontWeight: FontWeight.w600)),
                                                            )
                                                          else
                                                            const Text("—", style: TextStyle(color: Colors.white)),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Pagination
                                      if (totalPages > 1)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 16),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                onPressed: currentPage > 0 ? () => setState(() => currentPage--) : null,
                                                icon: const Icon(Icons.chevron_left),
                                              ),
                                              Text("Page ${currentPage + 1} of $totalPages"),
                                              IconButton(
                                                onPressed: currentPage < totalPages - 1 ? () => setState(() => currentPage++) : null,
                                                icon: const Icon(Icons.chevron_right),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: _exportToCsv, // Now calls the export function
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text("Export Orders as CSV"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
}

// Your original SidebarItem – unchanged
class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool active;
  final VoidCallback onTap;
  const _SidebarItem(this.icon, this.title, this.active, this.onTap, {Key? key}) : super(key: key);
  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: widget.active ? Colors.white.withOpacity(0.1) : (_hovering ? Colors.white.withOpacity(0.15) : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ListTile(
          leading: Icon(widget.icon, color: Colors.white),
          title: Text(widget.title, style: const TextStyle(color: Colors.white)),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}