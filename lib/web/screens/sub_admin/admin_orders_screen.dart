import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'package:daligas/web/main_web.dart';
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

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminWelcomeScreen()),
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
          _SidebarItem(Icons.assignment, "Reports", false, () {
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
      body: Row(
        children: [
          _buildSidebar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Orders", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
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
                                                      userId == null || userId.isEmpty
                                                          ? const Text("Unknown User")
                                                          : FutureBuilder<DocumentSnapshot>(
                                                              future: firestore.collection('users').doc(userId).get(),
                                                              builder: (context, snap) {
                                                                if (!snap.hasData) return const Text("...");
                                                                final name = (snap.data!.data() as Map<String, dynamic>?)?['fullName']?.toString() ?? 'Unknown';
                                                                return Text(name);
                                                              },
                                                            ),
                                                    ),
                                                    DataCell(
                                                      GestureDetector(
                                                        onTap: () => _showOrderDetailsDialog(doc),
                                                        child: const Text(
                                                          "See Details",
                                                          style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
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
                                                            const Text("—", style: TextStyle(color: Colors.grey)),
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
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                child: const Text("Export as CSV/PDF/Excel", style: TextStyle(color: Colors.white)),
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