import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/web/main_web.dart';
import 'package:intl/intl.dart';
import 'admin_welcome_screen.dart';
import 'super_sales_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

class SuperInventoryScreen extends StatefulWidget {
  const SuperInventoryScreen({super.key});
  @override
  State<SuperInventoryScreen> createState() => _SuperInventoryScreenState();
}

class _SuperInventoryScreenState extends State<SuperInventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 0; // For pagination

  Future<void> _logout(BuildContext context) async {
  await FirebaseAuth.instance.signOut();

  if (!context.mounted) {
    return;
  }

  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
}

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ───── Sidebar (unchanged) ─────
          Container(
            width: 220,
            color: const Color(0xFF0D2236),
            child: Column(
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
                    PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperAdminDashboard(), transitionDuration: Duration.zero),
                  );
                }),
                _SidebarItem(Icons.bar_chart, "Sales", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperSalesScreen(), transitionDuration: Duration.zero),
                  );
                }),
                _SidebarItem(Icons.inventory, "Inventory", true, () {}),
                _SidebarItem(Icons.people, "Employees", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperEmployeesScreen(), transitionDuration: Duration.zero),
                  );
                }),
                _SidebarItem(Icons.feedback, "Feedbacks", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperFeedbacksScreen(), transitionDuration: Duration.zero),
                  );
                }),
                _SidebarItem(Icons.assignment, "Business Reports", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperReportsScreen(), transitionDuration: Duration.zero),
                  );
                }),
                _SidebarItem(Icons.settings, "Settings", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperSettingsScreen(), transitionDuration: Duration.zero),
                  );
                }),
                const Spacer(),
                _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ───── Main Content ─────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Inventory", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),


                  // ───── Live Stat Cards ─────
                  StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('products').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(4, (_) => _statCard("...", "")),
                        );
                      }

                      final products = snapshot.data!.docs;

                      final totalStock = products.fold<int>(0, (sum, doc) {
                        final stock = doc['stock'];
                        return sum + (stock is num ? stock.toInt() : (stock is int ? stock : 0));
                      });

                      final lowStockCount = products.where((doc) {
                        final stock = doc['stock'];
                        final value = stock is num ? stock.toInt() : (stock is int ? stock : 0);
                        return value <= 5;
                      }).length;

                      final outOfStockCount = products.where((doc) {
                        final stock = doc['stock'];
                        final value = stock is num ? stock.toInt() : (stock is int ? stock : 0);
                        return value == 0;
                      }).length;

                      final today = DateTime.now();
                      final todayUpdatedCount = products.where((doc) {
                        final updatedAt = (doc['updatedAt'] as Timestamp?)?.toDate();
                        if (updatedAt == null) return false;
                        return updatedAt.year == today.year &&
                            updatedAt.month == today.month &&
                            updatedAt.day == today.day;
                      }).length;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _statCard(totalStock.toString(), "Total Stock"),
                          _statCard(lowStockCount.toString(), "Low Stock", color: Colors.orange),
                          _statCard(todayUpdatedCount.toString(), "Incoming Deliveries", color: Colors.blue),
                          _statCard(outOfStockCount.toString(), "Out of Stock", color: Colors.red),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // ───── FULL TABLE CARD (Search + Table + Paginator) ─────
                  Expanded(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          // Search Bar Inside Card
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val.toLowerCase();
                                  _currentPage = 0;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: "Search items...",
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),

                          // Table + Paginator
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: firestore.collection('products').orderBy('name').snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }

                                final filtered = snapshot.data!.docs.where((doc) {
                                  final name = (doc['name'] as String?)?.toLowerCase() ?? '';
                                  return name.contains(_searchQuery);
                                }).toList();

                                const itemsPerPage = 4;
                                final totalPages = (filtered.length / itemsPerPage).ceil();
                                final start = _currentPage * itemsPerPage;
                                final end = (start + itemsPerPage).clamp(0, filtered.length);
                                final pageItems = filtered.sublist(start, end);

                                return Column(
                                  children: [
                                    // Stretched Table
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          return SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                              child: DataTable(
                                                headingRowHeight: 56,
                                                dataRowHeight: 72,
                                                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                                columnSpacing: 32,
                                                horizontalMargin: 24,
                                                border: TableBorder.all(
                                                  color: Colors.grey.shade300,
                                                  width: 1,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                columns: const [
                                                  DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.w600))),
                                                  DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.w600))),
                                                  DataColumn(label: Text('Current Stock', style: TextStyle(fontWeight: FontWeight.w600))),
                                                  DataColumn(label: Text('Min Stock', style: TextStyle(fontWeight: FontWeight.w600))),
                                                  DataColumn(label: Text('Unit Price', style: TextStyle(fontWeight: FontWeight.w600))),
                                                  DataColumn(label: Text('Brand', style: TextStyle(fontWeight: FontWeight.w600))),
                                                  DataColumn(label: Text('Last Restock', style: TextStyle(fontWeight: FontWeight.w600))),
                                                ],
                                                rows: pageItems.map((doc) {
                                                  final data = doc.data() as Map<String, dynamic>;
                                                  final stock = (data['stock'] as num?)?.toInt() ?? 0;
                                                  final price = (data['price'] as num?)?.toDouble() ?? 0;
                                                  final updatedAt = data['updatedAt'] as Timestamp?;
                                                  final isLowStock = stock <= 5;

                                                  return DataRow(
                                                    color: WidgetStateProperty.all(isLowStock ? Colors.red.withOpacity(0.12) : null),
                                                    cells: [
                                                      DataCell(Text(data['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
                                                      DataCell(Text(data['category'] ?? '-')),
                                                      DataCell(Text(
                                                        stock.toString(),
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          color: stock == 0 ? Colors.red : (stock <= 5 ? Colors.orange.shade700 : Colors.black87),
                                                        ),
                                                      )),
                                                      DataCell(const Text('5')),
                                                      DataCell(Text('₱${price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                                                      DataCell(Text((data['brand'] ?? '-').toString().toUpperCase())),
                                                      DataCell(Text(updatedAt != null ? DateFormat('MMMM d, yyyy').format(updatedAt.toDate()) : '-')),
                                                    ],
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),

                                    // Paginator
                                    if (totalPages > 1)
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            IconButton(
                                              onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                                              icon: const Icon(Icons.chevron_left),
                                              disabledColor: Colors.grey.shade400,
                                            ),
                                            const SizedBox(width: 20),
                                            Text(
                                              "Page ${_currentPage + 1} of $totalPages",
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(width: 20),
                                            IconButton(
                                              onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                                              icon: const Icon(Icons.chevron_right),
                                              disabledColor: Colors.grey.shade400,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label, {Color? color}) {
    return Expanded(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color ?? Colors.black87)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 14, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

// ───── Sidebar Item (unchanged) ─────
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
          color: _hovering
              ? Colors.white.withOpacity(0.15)
              : (widget.active ? Colors.white.withOpacity(0.1) : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
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