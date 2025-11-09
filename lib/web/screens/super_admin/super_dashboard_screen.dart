import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart'; // For charts
import 'admin_welcome_screen.dart';
import 'super_sales_screen.dart';
import 'super_inventory_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

class SuperAdminDashboard extends StatelessWidget {
  const SuperAdminDashboard({super.key});

  // ✅ Logout method
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
                _SidebarItem(Icons.dashboard, "Dashboard", true, () {}),
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
                  const Text(
                    "Welcome Super Admin",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Top Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatCard(Icons.shopping_cart, "250", "Total Orders"),
                      _buildStatCard(Icons.attach_money, "₱123,456", "Total Sales"),
                      _buildStatCard(Icons.pending_actions, "20", "Pending Deliveries"),
                      _buildStatCard(Icons.star, "20", "Customer Ratings"),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Sales & Payment Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _buildChartCard()),
                      const SizedBox(width: 20),
                      Expanded(child: _buildPieChartCard()),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Top Products
                  _buildTopProductsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Stat Card
  Widget _buildStatCard(IconData icon, String value, String label) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Sales Line Chart
  Widget _buildChartCard() {
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
                  spots: const [
                    FlSpot(1, 3),
                    FlSpot(2, 5),
                    FlSpot(3, 4),
                    FlSpot(4, 7),
                    FlSpot(5, 3),
                    FlSpot(6, 5),
                    FlSpot(7, 9),
                  ],
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 3,
                  belowBarData: BarAreaData(show: false),
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, _) {
                      switch (val.toInt()) {
                        case 1:
                          return const Text("Jan");
                        case 2:
                          return const Text("Feb");
                        case 3:
                          return const Text("Mar");
                        case 4:
                          return const Text("Apr");
                        case 5:
                          return const Text("May");
                        case 6:
                          return const Text("Jun");
                        case 7:
                          return const Text("Jul");
                      }
                      return const Text("");
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ Pie Chart for Payment Methods
  Widget _buildPieChartCard() {
    return Card(
      elevation: 2,
      child: SizedBox(
        height: 250,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PieChart(
            PieChartData(
              sections: [
                PieChartSectionData(value: 40, title: "COD", color: Colors.yellow),
                PieChartSectionData(value: 30, title: "E-Wallet", color: Colors.red),
                PieChartSectionData(value: 30, title: "Bank", color: Colors.blueGrey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ Top Products
  Widget _buildTopProductsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Top Products",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildProgressBar("Product 1", 0.8),
            _buildProgressBar("Product 2", 0.5),
            _buildProgressBar("Product 3", 0.2),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(String title, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: value,
            color: Colors.blueGrey,
            backgroundColor: Colors.grey[300],
            minHeight: 12,
          ),
        ],
      ),
    );
  }
}

/// ✅ New widget for persistent hover
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
