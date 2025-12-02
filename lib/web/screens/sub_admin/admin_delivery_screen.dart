import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/main_web.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';

import 'admin_dashboard_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_feedbacks_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_screen.dart';

class AdminDeliveryScreen extends StatefulWidget {
  const AdminDeliveryScreen({super.key});

  @override
  State<AdminDeliveryScreen> createState() => _AdminDeliveryScreenState();
}

class _AdminDeliveryScreenState extends State<AdminDeliveryScreen> {
  String searchQuery = '';
  String selectedStatus = 'All';
  int currentPage = 0;
  final int itemsPerPage = 6;
  final TextEditingController searchController = TextEditingController();

  void _exportDeliveriesToCsv() async {
  try {
    // Fetch all relevant orders
    final ordersSnapshot = await firestore
        .collection('orders')
        .where('deliveryStatus', whereIn: ['Processing', 'Shipped', 'Delivered'])
        .get();

    // Fetch lookup data for employees and users
    final results = await Future.wait([
      firestore.collection('employees').get(),
      firestore.collection('users').get(),
    ]);

    final employees = {for (var d in results[0].docs) d.id: d.data()};
    final users = {for (var d in results[1].docs) d.id: d.data()};

    final rows = <List<String>>[];

    // Add header row
    rows.add([
      'Order ID',
      'Date & Time',
      'Customer Name',
      'Delivery Address',
      'Driver Name',
      'Delivery Status',
      'Total Amount',
      'Payment Method',
    ]);

    for (var doc in ordersSnapshot.docs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final status = data['deliveryStatus'] ?? 'Processing';
      final employeeId = data['employeeId'] as String?;
      final userId = data['userId'] as String?;
      final address = data['deliveryAddress'] ?? 'No address';
      final total = (data['total'] ?? 0).toDouble();
      final paymentMethod = data['paymentMethod'] ?? 'COD';

      final customerName = userId != null
          ? (users[userId]?['fullName'] as String?) ?? 'Unknown Customer'
          : 'Unknown Customer';

      final driverName = employeeId != null
          ? (employees[employeeId]?['name'] as String?) ?? 'Unknown Driver'
          : 'Not Assigned';

      rows.add([
        doc.id,
        DateFormat('MMMM d, yyyy - hh:mm a').format(createdAt),
        customerName,
        address,
        driverName,
        status,
        total.toStringAsFixed(2),
        paymentMethod.toUpperCase(),
      ]);
    }

    // Convert to CSV string
    final csvString = _simpleCsvConvert(rows);

    // Create and download the file
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final blob = html.Blob([utf8.encode(csvString)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'delivery_report_$timestamp.csv')
      ..click();

    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Delivery report exported successfully (${rows.length - 1} orders)'),
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error exporting deliveries: $e')),
    );
  }
}

// Add this helper method for CSV conversion
String _simpleCsvConvert(List<List<String>> rows) {
  String escapeCell(String cell) {
    if (cell.contains('"')) cell = cell.replaceAll('"', '""');
    if (cell.contains(',') || cell.contains('"') || cell.contains('\n')) {
      return '"$cell"';
    }
    return cell;
  }

  return rows.map((row) => row.map(escapeCell).join(',')).join('\r\n');
}

  Future<void> _logout(BuildContext context) async {
  await FirebaseAuth.instance.signOut();

  if (!context.mounted) {
    return;
  }

  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
}

  void _updateDeliveryStatus(String orderId, String newStatus) async {
    await firestore.collection('orders').doc(orderId).update({
      'deliveryStatus': newStatus,
      if (newStatus == 'Delivered') 'deliveredAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Order marked as $newStatus")),
    );
  }

  void _showAssignEmployeeDialog(String orderId, String? currentEmployeeId) async {
    final employeesSnap = await firestore.collection('employees').get();

    String? selectedId = currentEmployeeId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Assign Delivery Employee"),
        content: SizedBox(
          width: 420,
          child: DropdownButtonFormField<String>(
            value: selectedId,
            hint: const Text("Select an employee"),
            items: employeesSnap.docs.map((doc) {
              final data = doc.data();
              final name = data['name'] ?? 'No Name';
              final email = data['email'] ?? '';
              return DropdownMenuItem(
                value: doc.id,
                child: Text("$name ($email)"),
              );
            }).toList(),
            onChanged: (val) => selectedId = val,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: selectedId != null
                ? () async {
                    await firestore.collection('orders').doc(orderId).update({'employeeId': selectedId});
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Employee assigned successfully!")),
                    );
                  }
                : null,
            child: const Text("Assign"),
          ),
        ],
      ),
    );
  }

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
                child: const Text("DALI GAS",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 30),

          _SidebarItem(Icons.dashboard, "Dashboard", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminDashboardScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.shopping_cart, "Orders", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminOrdersScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.inventory, "Inventory", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminInventoryScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.local_shipping, "Delivery Management", true, () {}),
          _SidebarItem(Icons.feedback, "Feedback", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminFeedbackScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.flag, "User Reports", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminReportsScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.settings, "Settings", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminSettingsScreen(), transitionDuration: Duration.zero))),

          const Spacer(),
          _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Delivery Management", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // LIVE STATS
                  StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('orders').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Row(children: List.generate(3, (_) => _buildStatCard("...", "")));
                      }
                      int active = 0, completedToday = 0;
                      final today = DateTime.now();

                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final status = data['deliveryStatus'] ?? 'Processing';
                        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

                        if (status == 'Shipped') active++;
                        if (status == 'Delivered' && createdAt != null && createdAt.day == today.day) completedToday++;
                      }

                      return Row(
                        children: [
                          _buildStatCard(active.toString(), "Active Deliveries"),
                          const SizedBox(width: 16),
                          _buildStatCard(completedToday.toString(), "Completed Today"),
                          const SizedBox(width: 16),
                          _buildStatCard("0", "Delayed"),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  Expanded(
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: searchController,
                                    onChanged: (val) => setState(() {
                                      searchQuery = val.toLowerCase();
                                      currentPage = 0;
                                    }),
                                    decoration: const InputDecoration(
                                      hintText: "Search by employee, customer, address...",
                                      prefixIcon: Icon(Icons.search),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<String>(
                                    value: selectedStatus,
                                    items: ['All', 'Processing', 'Shipped', 'Delivered']
                                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                        .toList(),
                                    onChanged: (val) => setState(() {
                                      selectedStatus = val!;
                                      currentPage = 0;
                                    }),
                                    decoration: const InputDecoration(
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // MAIN TABLE
                            Expanded(
                              child: StreamBuilder<QuerySnapshot>(
                                stream: firestore
                                    .collection('orders')
                                    .where('deliveryStatus', whereIn: ['Processing', 'Shipped', 'Delivered'])
                                    .orderBy('createdAt', descending: true)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                                  final orderDocs = snapshot.data!.docs;

                                  return FutureBuilder<Map<String, Map<String, dynamic>>>(
                                    future: Future.wait([
                                      firestore.collection('employees').get(),
                                      firestore.collection('users').get(),
                                    ]).then((results) {
                                      final empMap = {for (var d in results[0].docs) d.id: d.data()};
                                      final userMap = {for (var d in results[1].docs) d.id: d.data()};
                                      return {'employees': empMap, 'users': userMap};
                                    }),
                                    builder: (context, lookupSnapshot) {
                                      if (!lookupSnapshot.hasData) {
                                        return const Center(child: CircularProgressIndicator());
                                      }

                                      final employees = lookupSnapshot.data!['employees'] as Map<String, Map<String, dynamic>>;
                                      final users = lookupSnapshot.data!['users'] as Map<String, Map<String, dynamic>>;

                                      final filteredDocs = orderDocs.where((doc) {
                                        final data = doc.data() as Map<String, dynamic>;
                                        final status = data['deliveryStatus'] ?? 'Processing';
                                        final employeeId = data['employeeId'] as String?;
                                        final userId = data['userId'] as String?;
                                        final address = (data['deliveryAddress'] ?? '').toString().toLowerCase();
                                        final orderId = doc.id.toLowerCase();

                                        final employeeName = employeeId != null
                                            ? (employees[employeeId]?['name'] ?? '').toString().toLowerCase()
                                            : '';
                                        final customerName = userId != null
                                            ? (users[userId]?['fullName'] ?? '').toString().toLowerCase()
                                            : '';

                                        final matchesStatus = selectedStatus == 'All' || status == selectedStatus;
                                        final matchesSearch = searchQuery.isEmpty ||
                                            orderId.contains(searchQuery) ||
                                            employeeName.contains(searchQuery) ||
                                            customerName.contains(searchQuery) ||
                                            address.contains(searchQuery);

                                        return matchesStatus && matchesSearch;
                                      }).toList();

                                      final totalPages = (filteredDocs.length / itemsPerPage).ceil();
                                      if (currentPage >= totalPages && totalPages > 0) currentPage = totalPages - 1;
                                      final start = currentPage * itemsPerPage;
                                      final pageDocs = filteredDocs.sublist(start, (start + itemsPerPage).clamp(0, filteredDocs.length));

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
                                                  border: TableBorder(
                                                    horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1),
                                                  ),
                                                  columns: const [
                                                    DataColumn(label: Text("Date & Time", style: TextStyle(fontWeight: FontWeight.w600))),
                                                    DataColumn(label: Text("Driver", style: TextStyle(fontWeight: FontWeight.w600))),
                                                    DataColumn(label: Text("Customer", style: TextStyle(fontWeight: FontWeight.w600))),
                                                    DataColumn(label: Text("Address", style: TextStyle(fontWeight: FontWeight.w600))),
                                                    DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.w600))),
                                                    DataColumn(label: Text("Action", style: TextStyle(fontWeight: FontWeight.w600))),
                                                  ],
                                                  rows: pageDocs.map((doc) {
                                                    final data = doc.data() as Map<String, dynamic>;
                                                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                                                    final status = data['deliveryStatus'] ?? 'Processing';
                                                    final employeeId = data['employeeId'] as String?;
                                                    final userId = data['userId'] as String?;
                                                    final address = data['deliveryAddress'] ?? 'No address';

                                                    final driverName = employeeId != null
                                                        ? (employees[employeeId]?['name'] as String?) ?? 'Unknown Driver'
                                                        : 'Not Assigned';

                                                    final customerName = userId != null
                                                        ? (users[userId]?['fullName'] as String?) ?? 'Unknown Customer'
                                                        : 'Unknown Customer';

                                                    return DataRow(cells: [
                                                      DataCell(Text(DateFormat('MMMM d, yyyy – hh:mm a').format(createdAt))),
                                                      DataCell(Text(driverName, style: TextStyle(color: employeeId == null ? Colors.orange : null))),
                                                      DataCell(Text(customerName)),
                                                      DataCell(Text(address.length > 40 ? '${address.substring(0, 40)}...' : address)),

                                                      // Status Pill - Exactly like original
                                                      DataCell(Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: status == 'Delivered'
                                                              ? Colors.green.shade50
                                                              : status == 'Shipped'
                                                                  ? Colors.blue.shade50
                                                                  : Colors.orange.shade50,
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(
                                                          status == 'Shipped' ? "On the Way" : status,
                                                          style: TextStyle(
                                                            color: status == 'Delivered'
                                                                ? Colors.green
                                                                : status == 'Shipped'
                                                                    ? Colors.blue
                                                                    : Colors.orange,
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      )),

                                                      // Action Button - Exactly like original
DataCell(
                                                        status == 'Processing'
                                                            ? ElevatedButton(
                                                                onPressed: () => _showAssignEmployeeDialog(doc.id, employeeId),
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor: Colors.orange,
                                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                                ),
                                                                child: const Text("Assign Driver", style: TextStyle(color: Colors.white)),
                                                              )
                                                            : status == 'Shipped'
                                                                ? OutlinedButton(
                                                                    onPressed: () => _updateDeliveryStatus(doc.id, 'Delivered'),
                                                                    style: OutlinedButton.styleFrom(
                                                                      foregroundColor: Colors.black87,
                                                                      backgroundColor: Colors.grey.shade200,
                                                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                                    ),
                                                                    child: const Text("Mark Delivered"),
                                                                  )
                                                                : const SizedBox(), // Nothing shown when Delivered
                                                      ),
                                                    ]);
                                                  }).toList(),
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (totalPages > 1)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 16),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  IconButton(onPressed: currentPage > 0 ? () => setState(() => currentPage--) : null, icon: const Icon(Icons.chevron_left)),
                                                  Text("Page ${currentPage + 1} of $totalPages"),
                                                  IconButton(onPressed: currentPage < totalPages - 1 ? () => setState(() => currentPage++) : null, icon: const Icon(Icons.chevron_right)),
                                                ],
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 16),
                            Align(
  alignment: Alignment.centerRight,
  child: ElevatedButton.icon(
    onPressed: _exportDeliveriesToCsv,
    icon: const Icon(
      Icons.download, 
      size: 18,
      color: Colors.white,  // Explicitly set the icon color to white
    ),
    label: const Text("Export Deliveries", style: TextStyle(color: Colors.white)),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.blue,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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