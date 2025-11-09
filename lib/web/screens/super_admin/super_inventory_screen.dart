import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_welcome_screen.dart';
import 'super_sales_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

class SuperInventoryScreen extends StatelessWidget {
  const SuperInventoryScreen({super.key});

  // ✅ Logout
  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminWelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Sidebar ----
          Container(
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
                _SidebarItem(Icons.dashboard, "Dashboard", true, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SuperAdminDashboard(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                }),
                _SidebarItem(Icons.bar_chart, "Sales", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                     pageBuilder: (_, __, ___) => const SuperSalesScreen(),
                     transitionDuration: Duration.zero,
                     reverseTransitionDuration: Duration.zero,
                   ),
                 );
                }),
                _SidebarItem(Icons.inventory, "Inventory", true, () {}),
                _SidebarItem(Icons.people, "Employees", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SuperEmployeesScreen(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                }),
                _SidebarItem(Icons.feedback, "Feedbacks", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SuperFeedbacksScreen(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                }),
                _SidebarItem(Icons.assignment, "Reports", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SuperReportsScreen(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                }),
                _SidebarItem(Icons.settings, "Settings", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SuperSettingsScreen(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                }),
                const Spacer(),
                _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
              ],
            ),
          ),

          // ---- Main Content ----
          Expanded(
            // No SingleChildScrollView -> page is NOT scrollable
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Inventory",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Top Stat Cards
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statCard("1,234", "Total Stock"),
                      _statCard("34", "Low Stock"),
                      _statCard("20", "Incoming Deliveries"),
                      _statCard("5", "Out of Stock"),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Search Bar
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 250,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: "Search",
                          prefixIcon: const Icon(Icons.search),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ✅ Inventory Table with horizontal scroll only
                  Expanded(
                    child: _inventoryTable(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Inventory Table (horizontal scroll only)
  Widget _inventoryTable() {
    final rows = [
      ["LPG Tank 11kg", "Gas", "120", "20", "₱800", "Regasco", "09-18-2025"],
      ["LPG Tank 5kg", "Gas", "60", "15", "₱400", "Petron", "09-17-2025"],
      ["Burner Stove", "Accessory", "35", "10", "₱1500", "Appliance Co.", "09-15-2025"],
      ["Valve Set", "Accessory", "80", "25", "₱250", "GasWorks", "09-14-2025"],
      ["Regulator", "Accessory", "40", "10", "₱350", "Regasco", "09-13-2025"],
    ];

    return Card(
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, // ✅ Only horizontal scroll remains
        child: SizedBox(
          width: 1500, // wide fixed table
          child: DataTable(
            columnSpacing: 30,
            columns: const [
              DataColumn(label: Text("Item")),
              DataColumn(label: Text("Category")),
              DataColumn(label: Text("Current Stock")),
              DataColumn(label: Text("Min Stock")),
              DataColumn(label: Text("Unit Price")),
              DataColumn(label: Text("Supplier")),
              DataColumn(label: Text("Last Restock")),
            ],
            rows: rows.map((row) {
              final current = int.tryParse(row[2]) ?? 0;
              final min = int.tryParse(row[3]) ?? 0;
              final lowStock = current <= min;

              return DataRow(
                color: MaterialStateProperty.resolveWith<Color?>(
                  (Set<MaterialState> states) {
                    if (lowStock) return Colors.red.withOpacity(0.1);
                    return null;
                  },
                ),
                cells: [
                  for (int i = 0; i < row.length; i++) DataCell(Text(row[i])),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ✅ Stat Card
  Widget _statCard(String value, String label) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

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
