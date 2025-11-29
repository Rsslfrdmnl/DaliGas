import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_welcome_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_sales_screen.dart';
import 'super_inventory_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_settings_screen.dart';

class SuperReportsScreen extends StatefulWidget {
  const SuperReportsScreen({super.key});

  @override
  State<SuperReportsScreen> createState() => _SuperReportsScreenState();
}

class _SuperReportsScreenState extends State<SuperReportsScreen> {
  DateTimeRange? _selectedRange;
  String _selectedReportType = "All";

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

  // ✅ Date Picker
  Future<void> _pickDateRange() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(now.year - 5);
    final DateTime lastDate = DateTime(now.year + 1);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: _selectedRange ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );

    if (picked != null) {
      setState(() => _selectedRange = picked);
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
                _SidebarItem(Icons.dashboard, "Dashboard", false, () {
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
                _SidebarItem(Icons.assignment, "Reports", true, () {}),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Reports",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ✅ Summary Cards
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statCard(Icons.attach_money, "₱250,000", "Total Sales"),
                      _statCard(Icons.inventory, "540", "Inventory Items"),
                      _statCard(Icons.people, "32", "Employees"),
                      _statCard(Icons.feedback, "120", "Feedback Received"),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // ✅ Filters Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                           // Date Range Selector
                            ElevatedButton.icon(
                              icon: const Icon(Icons.date_range, color: Colors.white),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0D2236),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                              onPressed: _pickDateRange,
                              label: Text(
                                _selectedRange == null
                                    ? "Select Date Range"
                                    : "${_selectedRange!.start.toLocal().toString().split(' ')[0]} - ${_selectedRange!.end.toLocal().toString().split(' ')[0]}",
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 20),

                            // Dropdown for Report Type
                            SizedBox(
                              width: 200,
                              child: DropdownButtonFormField<String>(
                                value: _selectedReportType,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Color(0xFFF9F6FB),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(value: "All", child: Text("All Reports")),
                                  DropdownMenuItem(value: "Sales", child: Text("Sales")),
                                  DropdownMenuItem(value: "Inventory", child: Text("Inventory")),
                                  DropdownMenuItem(value: "Employees", child: Text("Employees")),
                                  DropdownMenuItem(value: "Feedback", child: Text("Feedback")),
                                ],
                                onChanged: (val) => setState(() => _selectedReportType = val!),
                              ),
                            ),
                          ],
                        ),

                      ElevatedButton(
                        onPressed: () {
                          // TODO: Export report logic
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D2236),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
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

                  // ✅ Reports Table
                  Expanded(child: _reportsTable()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Stat Card
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

  // ✅ Reports Table (dummy data)
  Widget _reportsTable() {
    final rows = [
      ["RPT001", "Sales", "Monthly Sales Report", "09-01-2025", "Generated"],
      ["RPT002", "Inventory", "Stock Report", "09-02-2025", "Generated"],
      ["RPT003", "Employees", "Attendance Summary", "09-03-2025", "Pending"],
    ];

    return Card(
      elevation: 2,
      child: SizedBox(
        width: 1500, // ✅ Table width
        child: DataTable(
          columnSpacing: 40,
          columns: const [
            DataColumn(label: Text("Report ID")),
            DataColumn(label: Text("Type")),
            DataColumn(label: Text("Title")),
            DataColumn(label: Text("Date Generated")),
            DataColumn(label: Text("Status")),
          ],
          rows: rows.map((row) {
            final status = row[4];
            final generated = status == "Generated";

            return DataRow(
              cells: [
                DataCell(Text(row[0])),
                DataCell(Text(row[1])),
                DataCell(Text(row[2])),
                DataCell(Text(row[3])),
                DataCell(
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: generated
                          ? Colors.green.withOpacity(0.2)
                          : Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: generated ? Colors.green : Colors.orange,
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
}

/// ✅ Sidebar Item with Hover
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
