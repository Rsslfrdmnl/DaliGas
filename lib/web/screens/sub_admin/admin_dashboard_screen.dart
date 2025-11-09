import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ added
import 'package:fl_chart/fl_chart.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_feedbacks_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
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
          _SidebarItem(Icons.dashboard, "Dashboard", true, () {}),
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

  // ✅ Real-time stat cards
  Widget _buildLiveStatCard(String title, IconData icon, Color color, Stream<QuerySnapshot> stream) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildStatCard(title, '...', icon, color);
        }
        final count = snapshot.data!.docs.length.toString();
        return _buildStatCard(title, count, icon, color);
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, color: Colors.black54)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersChart() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Orders",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                          if (value.toInt() >= 0 && value.toInt() < days.length) {
                            return Text(days[value.toInt()]);
                          }
                          return const Text("");
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: const [
                        FlSpot(0, 5),
                        FlSpot(1, 12),
                        FlSpot(2, 10),
                        FlSpot(3, 25),
                        FlSpot(4, 8),
                        FlSpot(5, 20),
                        FlSpot(6, 35),
                      ],
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryChart() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Delivery Performance",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return const Text("Delivered");
                            case 1:
                              return const Text("Late");
                            case 2:
                              return const Text("Cancelled");
                          }
                          return const Text("");
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [BarChartRodData(toY: 9, color: Colors.blue)],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [BarChartRodData(toY: 6, color: Colors.orange)],
                    ),
                    BarChartGroupData(
                      x: 2,
                      barRods: [BarChartRodData(toY: 2, color: Colors.red)],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Welcome Sub Admin",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // ✅ Real-time stat cards
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildLiveStatCard(
                          "New Orders",
                          Icons.shopping_cart,
                          Colors.blue,
                          FirebaseFirestore.instance
                              .collection('orders')
                              .where('status', isEqualTo: 'Pending')
                              .snapshots(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildLiveStatCard(
                          "Deliveries in Progress",
                          Icons.local_shipping,
                          Colors.green,
                          FirebaseFirestore.instance
                              .collection('deliveries')
                              .where('status', isEqualTo: 'In Progress')
                              .snapshots(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildLiveStatCard(
                          "Inventory Low Stock",
                          Icons.inventory,
                          Colors.orange,
                          FirebaseFirestore.instance
                              .collection('products')
                              .where('stock', isLessThanOrEqualTo: 5)
                              .snapshots(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildLiveStatCard(
                          "Feedback Pending",
                          Icons.feedback,
                          Colors.purple,
                          FirebaseFirestore.instance
                              .collection('feedbacks')
                              .where('status', isEqualTo: 'Pending')
                              .snapshots(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ✅ Charts row (unchanged)
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildOrdersChart()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildDeliveryChart()),
                      ],
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
