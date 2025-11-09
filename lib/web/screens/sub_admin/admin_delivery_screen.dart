import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminWelcomeScreen()),
      );
    }
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
                child: Image.asset(
                  "assets/images/daligas_logo.png",
                  height: 80,
                ),
              ),
              Transform.translate(
                offset: const Offset(-22, 0),
                child: const Text(
                  "DALI GAS",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          // Sidebar items
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
          _SidebarItem(Icons.shopping_cart, "Orders", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminOrdersScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
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
          _SidebarItem(Icons.local_shipping, "Delivery Management", true, () {}),
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

  // Stat Card (Orders/Inventory style)
  Widget _buildStatCard(String value, String title) {
    return Expanded(
      child: Card(
        elevation: 2,
        color: const Color(0xFFF9F6FB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Deliveries Table
  Widget _buildDeliveryTable() {
    return Container(
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
          DataColumn(
              label: Text("Date & Time",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label:
                  Text("Driver", style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label: Text("Customer",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label: Text("Address",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label: Text("Status",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label: Text("Action",
                  style: TextStyle(fontWeight: FontWeight.w600))),
        ],
        rows: [
          DataRow(
            cells: [
              const DataCell(Text("09/30/2025 - 11:30 AM")),
              const DataCell(Text("Juan Dela Cruz")),
              const DataCell(Text("Kerelia M.")),
              const DataCell(Text("123 Main Street, QC")),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "On the Way",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              )),
              DataCell(
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor: Colors.grey.shade200,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text("Update"),
                ),
              ),
            ],
          ),
        ],
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
                  const Text("Delivery Management",
                      style:
                          TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // Stat cards
                  Row(
                    children: [
                      _buildStatCard("5", "Active Deliveries"),
                      const SizedBox(width: 16),
                      _buildStatCard("12", "Completed Today"),
                      const SizedBox(width: 16),
                      _buildStatCard("1", "Delayed Deliveries"),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Main Deliveries card
                  Expanded(
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Search + Filters row
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: "Search by driver/customer",
                                      prefixIcon: const Icon(Icons.search),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 160,
                                  child: DropdownButtonFormField<String>(
                                    value: "All",
                                    items: const [
                                      DropdownMenuItem(
                                          value: "All", child: Text("All")),
                                      DropdownMenuItem(
                                          value: "On the Way",
                                          child: Text("On the Way")),
                                      DropdownMenuItem(
                                          value: "Delivered",
                                          child: Text("Delivered")),
                                      DropdownMenuItem(
                                          value: "Delayed",
                                          child: Text("Delayed")),
                                    ],
                                    onChanged: (_) {},
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Deliveries table
                            Expanded(
                              child: SingleChildScrollView(
                                child: _buildDeliveryTable(),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Export button
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6)),
                                ),
                                child: const Text("Export as CSV/PDF/Excel",
                                    style: TextStyle(color: Colors.white)),
                              ),
                            )
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

// Sidebar Item (reused)
class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool active;
  final VoidCallback onTap;

  const _SidebarItem(this.icon, this.title, this.active, this.onTap, {Key? key})
      : super(key: key);

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
          color: widget.active
              ? Colors.white.withOpacity(0.1)
              : (_hovering
                  ? Colors.white.withOpacity(0.15)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ListTile(
          leading: Icon(widget.icon, color: Colors.white),
          title: Text(widget.title,
              style: const TextStyle(color: Colors.white)),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}
