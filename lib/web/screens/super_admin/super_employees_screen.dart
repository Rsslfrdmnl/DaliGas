import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_welcome_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_sales_screen.dart';
import 'super_inventory_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

class SuperEmployeesScreen extends StatelessWidget {
  const SuperEmployeesScreen({super.key});

  // ✅ Logout function reused
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
          // ----- Sidebar -----
          Container(
            width: 220,
            color: const Color(0xFF0D2236),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                // Logo
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
                // Sidebar Menu
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
                _SidebarItem(Icons.inventory, "Inventory", false, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SuperInventoryScreen(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                }),
                _SidebarItem(Icons.people, "Employees", true, () {}),
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

          // ----- Main Content -----
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Row with Add Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Employees",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E88E5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () {
                          // TODO: Add employee logic
                        },
                        icon: const Icon(Icons.person_add, color: Colors.white),
                        label: const Text(
                          "Add Employee",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Employees Table
                  _employeesTable(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ Employees Table UI with fixed width and horizontal scroll only
  Widget _employeesTable() {
    final rows = [
      ["Russel M.", "Manager", "Operations", "0917-000-0000", "Active"],
      ["Jane D.", "Sales Associate", "Sales", "0917-111-1111", "Inactive"],
      ["Carlos P.", "Driver", "Logistics", "0917-222-2222", "Active"],
      ["Mary A.", "Inventory Clerk", "Warehouse", "0917-333-3333", "Active"],
    ];

    return Card(
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1500, // ✅ Fixed table width
          child: DataTable(
            columnSpacing: 30,
            columns: const [
              DataColumn(label: Text("Name")),
              DataColumn(label: Text("Role")),
              DataColumn(label: Text("Department")),
              DataColumn(label: Text("Contact")),
              DataColumn(label: Text("Status")),
            ],
            rows: rows.map((row) {
              final status = row[4];
              final isActive = status == "Active";
              return DataRow(
                cells: [
                  DataCell(Text(row[0])),
                  DataCell(Text(row[1])),
                  DataCell(Text(row[2])),
                  DataCell(Text(row[3])),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.green.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: isActive ? Colors.green : Colors.red,
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
              : (widget.active
                  ? Colors.white.withOpacity(0.1)
                  : Colors.transparent),
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
