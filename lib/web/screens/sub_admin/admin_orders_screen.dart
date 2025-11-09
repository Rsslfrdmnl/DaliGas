import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
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

  // Stat card
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
              Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  // Orders table
  Widget _buildOrdersTable() {
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
              label: Text("Customer",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label: Text("Order Details",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label: Text("Payment",
                  style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label:
                  Text("Status", style: TextStyle(fontWeight: FontWeight.w600))),
          DataColumn(
              label:
                  Text("Action", style: TextStyle(fontWeight: FontWeight.w600))),
        ],
        rows: [
          DataRow(
            cells: [
              const DataCell(Text("09/19/2025 - 10:00 AM")),
              const DataCell(Text("Kerelia M.")),
              const DataCell(Text("Regasco")),
              const DataCell(Text("GCash")),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "New",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    inherit: true,
                  ),
                ),
              )),
              DataCell(
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor: Colors.grey.shade200,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      inherit: true,
                    ),
                  ),
                  child: const Text(
                    "Confirm",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      inherit: true,
                    ),
                  ),
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
                  const Text("Orders",
                      style:
                          TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // Stat cards
                  Row(
                    children: [
                      _buildStatCard("12", "New Orders Today"),
                      const SizedBox(width: 16),
                      _buildStatCard("8", "Pending Deliveries"),
                      const SizedBox(width: 16),
                      _buildStatCard("45", "Completed Orders"),
                      const SizedBox(width: 16),
                      _buildStatCard("2", "Cancelled Orders"),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Main Orders card
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
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Row(
                                children: [
                                  // Search bar
                                  Expanded(
                                    child: TextField(
                                      decoration: InputDecoration(
                                        hintText: "Search by name/order ID",
                                        prefixIcon: const Icon(Icons.search),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: Colors.grey),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Date Range filter
                                  SizedBox(
                                    width: 180,
                                    child: DropdownButtonFormField<String>(
                                      value: "Date Range",
                                      items: const [
                                        DropdownMenuItem(
                                            value: "Date Range",
                                            child: Text("Date Range")),
                                        DropdownMenuItem(
                                            value: "Today", child: Text("Today")),
                                        DropdownMenuItem(
                                            value: "This Week",
                                            child: Text("This Week")),
                                        DropdownMenuItem(
                                            value: "This Month",
                                            child: Text("This Month")),
                                      ],
                                      onChanged: (_) {},
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Status filter
                                  SizedBox(
                                    width: 160,
                                    child: DropdownButtonFormField<String>(
                                      value: "All",
                                      items: const [
                                        DropdownMenuItem(
                                            value: "All", child: Text("All")),
                                        DropdownMenuItem(
                                            value: "New", child: Text("New")),
                                        DropdownMenuItem(
                                            value: "Confirmed",
                                            child: Text("Confirmed")),
                                        DropdownMenuItem(
                                            value: "Completed",
                                            child: Text("Completed")),
                                      ],
                                      onChanged: (_) {},
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Orders table
                            Expanded(
                              child: SingleChildScrollView(
                                child: _buildOrdersTable(),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Export button aligned right
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

// Sidebar Item widget
class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool active;
  final VoidCallback onTap;

  const _SidebarItem(this.icon, this.title, this.active, this.onTap,
      {Key? key})
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
              : (_hovering ? Colors.white.withOpacity(0.15) : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ListTile(
          leading: Icon(widget.icon, color: Colors.white),
          title:
              Text(widget.title, style: const TextStyle(color: Colors.white)),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}
