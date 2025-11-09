import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'admin_welcome_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_inventory_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

// Sidebar item widget
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

class SuperSalesScreen extends StatelessWidget {
  const SuperSalesScreen({super.key});

  // Logout function
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
        children: [
          // Sidebar
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
                // Sidebar items
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
                _SidebarItem(Icons.bar_chart, "Sales", true, () {}),
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
          // Main Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with search
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Sales",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search',
                            prefixIcon: const Icon(Icons.search),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Top Stats
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statCard("₱123,456", "Total Sales"),
                      _statCard("250", "Total Orders"),
                      _statCard("₱1,400", "Average order Value"),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Charts
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _salesLineChart(),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _paymentPieChart(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Transaction Table
                  _transactionTable(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _salesLineChart() {
    return Card(
      elevation: 2,
      child: SizedBox(
        height: 250,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 3,
                  spots: const [
                    FlSpot(1, 3),
                    FlSpot(2, 7),
                    FlSpot(3, 5),
                    FlSpot(4, 10),
                    FlSpot(5, 4),
                    FlSpot(6, 8),
                    FlSpot(7, 15),
                  ],
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, _) {
                      const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
                      if (val.toInt() >= 1 && val.toInt() <= 7) {
                        return Text(days[val.toInt() - 1]);
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true),
                ),
              ),
              gridData: FlGridData(show: true),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentPieChart() {
    return Card(
      elevation: 2,
      child: SizedBox(
        height: 250,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PieChart(
            PieChartData(
              sections: [
                PieChartSectionData(value: 40, color: Colors.yellow, title: 'COD'),
                PieChartSectionData(value: 30, color: Colors.red, title: 'E-Wallet'),
                PieChartSectionData(value: 30, color: Colors.blueGrey, title: 'Bank'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _transactionTable() {
    final rows = [
      ["TRNX001", "09-18-2025", "Keyserlle M.", "Regasco", "1", "₱500", "Cash", "Completed"],
      ["TRNX002", "09-17-2025", "Abdul J.", "Regasco", "2", "₱1000", "Gcash", "Completed"],
      ["TRNX003", "09-16-2025", "Pauline K.", "Regasco", "1", "₱800", "Gcash", "Completed"],
      ["TRNX004", "09-15-2025", "Russel F.", "Regasco", "3", "₱1500", "Bank Transfer", "Cancelled"],
      ["TRNX005", "09-15-2025", "Zacharry M.", "Regasco", "2", "₱1000", "Gcash", "Completed"],
    ];

    return Card(
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          width: 1500, // Adjusted wider table
          child: DataTable(
            columnSpacing: 30, // Added for better column spacing
            columns: const [
              DataColumn(label: Text("Transaction ID")),
              DataColumn(label: Text("Date")),
              DataColumn(label: Text("Customer")),
              DataColumn(label: Text("Product")),
              DataColumn(label: Text("Quantity")),
              DataColumn(label: Text("Total Amount")),
              DataColumn(label: Text("Payment Method")),
              DataColumn(label: Text("Status")),
            ],
            rows: rows.map((row) {
              final status = row[7];
              Color bgColor;
              if (status == "Completed") {
                bgColor = Colors.green.withOpacity(0.2);
              } else if (status == "Cancelled") {
                bgColor = Colors.red.withOpacity(0.2);
              } else {
                bgColor = Colors.grey.withOpacity(0.2);
              }
              return DataRow(
                cells: [
                  for (int i = 0; i < 7; i++) DataCell(Text(row[i])),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: status == "Completed" ? Colors.green : Colors.red,
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