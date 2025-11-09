import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_screen.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
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

          // Sidebar Items
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
          _SidebarItem(Icons.feedback, "Feedback", true, () {}),
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

  // ✅ Stat Card like super_feedbacks_screen
  Widget _statCard(IconData icon, String value, String label) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 36, color: const Color(0xFF0D2236)),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Feedback Table (copied style from super_feedbacks_screen)
  Widget _feedbackTable() {
    final rows = [
      ["FB001", "Product", "Juan Dela Cruz", "5", "09-20-2025", "Resolved"],
      ["FB002", "Service", "Maria Santos", "4", "09-19-2025", "Pending"],
      ["FB003", "Delivery", "Carlos Reyes", "5", "09-18-2025", "Resolved"],
    ];

    return Card(
      elevation: 2,
      child: SizedBox(
        width: 1500, // ✅ Fixed table width
        child: DataTable(
          columnSpacing: 40,
          columns: const [
            DataColumn(label: Text("Feedback ID")),
            DataColumn(label: Text("Type")),
            DataColumn(label: Text("Name")),
            DataColumn(label: Text("Rating")),
            DataColumn(label: Text("Date Submitted")),
            DataColumn(label: Text("Status")),
          ],
          rows: rows.map((row) {
            final status = row[5];
            final resolved = status == "Resolved";

            return DataRow(
              cells: [
                DataCell(Text(row[0])),
                DataCell(Text(row[1])),
                DataCell(Text(row[2])),
                DataCell(Text(row[3])),
                DataCell(Text(row[4])),
                DataCell(
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: resolved
                          ? Colors.green.withOpacity(0.2)
                          : Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: resolved ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FA),
      body: Row(
        children: [
          _buildSidebar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Feedbacks",
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                  const SizedBox(height: 20),

                  // ✅ Stat cards row
                  Row(
                    children: [
                      _statCard(Icons.star, "4.5", "Average Rating"),
                      const SizedBox(width: 16),
                      _statCard(Icons.feedback, "120", "Total Feedback"),
                      const SizedBox(width: 16),
                      _statCard(Icons.check_circle, "95", "Resolved"),
                      const SizedBox(width: 16),
                      _statCard(Icons.hourglass_bottom, "25", "Pending Feedback"),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // ✅ Title + Export Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Customer Feedbacks",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          // TODO: Export logic
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D2236),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text(
                          "Export",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ✅ Feedback Table
                  Expanded(
                    child: SingleChildScrollView(
                      child: _feedbackTable(),
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

// Sidebar Item (unchanged)
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
