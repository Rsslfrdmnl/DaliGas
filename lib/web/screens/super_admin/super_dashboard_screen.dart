// lib/web/screens/super_admin/super_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'package:daligas/web/main_web.dart';
import 'super_sales_screen.dart';
import 'super_inventory_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  final NumberFormat currency = NumberFormat.currency(locale: 'fil_PH', symbol: '₱');

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminWelcomeScreen()),
      );
    }
  }

  Timestamp get _startOfToday => Timestamp.fromDate(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      );

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
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Welcome, Super Admin", style: Theme.of(context).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),

                  // TOP STAT CARDS — FULL WIDTH, HORIZONTAL LAYOUT
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        children: [
                          Expanded(child: _FullWidthStatCard(
                            title: "Total Customers",
                            icon: Icons.people,
                            color: Colors.purple.shade600,
                            stream: firestore.collection('users').snapshots(),
                            valueBuilder: (snap) => snap.docs.length.toString(),
                          )),
                          const SizedBox(width: 20),
                          Expanded(child: _FullWidthStatCard(
                            title: "Total Revenue",
                            icon: Icons.trending_up,
                            color: Colors.green.shade600,
                            stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Delivered').snapshots(),
                            valueBuilder: (snap) {
                              double total = 0.0;
                              for (var doc in snap.docs) {
                                final data = doc.data() as Map<String, dynamic>;
                                final amount = data['total'] as num?;
                                total += (amount?.toDouble() ?? 0.0);
                              }
                              return currency.format(total);
                            },
                          )),
                          const SizedBox(width: 20),
                          Expanded(child: _FullWidthStatCard(
                            title: "Today's Orders",
                            icon: Icons.today,
                            color: Colors.orange.shade600,
                            stream: firestore.collection('orders').where('createdAt', isGreaterThanOrEqualTo: _startOfToday).snapshots(),
                            valueBuilder: (snap) => snap.docs.length.toString(),
                          )),
                          const SizedBox(width: 20),
                          Expanded(child: _FullWidthStatCard(
                            title: "Pending Deliveries",
                            icon: Icons.pending_actions,
                            color: Colors.red.shade600,
                            stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Processing').snapshots(),
                            valueBuilder: (snap) => snap.docs.length.toString(),
                          )),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Charts
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _RevenueChart()),
                      const SizedBox(width: 20),
                      Expanded(child: _PaymentMethodPieChart()),
                    ],
                  ),

                  const SizedBox(height: 32),
                  _TopProductsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateTo(Widget page) {
    Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => page, transitionDuration: Duration.zero));
  }
}

// Revenue Chart (Last 7 Days) – uses correct 'total' field
class _RevenueChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Revenue Trend (Last 7 Days)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: StreamBuilder<QuerySnapshot>(
                stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Delivered').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  final now = DateTime.now();
                  final days = List.generate(7, (i) => DateTime(now.year, now.month, now.day - (6 - i)));
                  final Map<DateTime, double> dailyRevenue = {for (var d in days) DateTime(d.year, d.month, d.day): 0.0};

                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final deliveredAt = data['deliveredAt'] as Timestamp?;
                    if (deliveredAt == null) continue;

                    final date = deliveredAt.toDate();
                    final key = DateTime(date.year, date.month, date.day);
                    if (dailyRevenue.containsKey(key)) {
                      final amount = data['total'] as num?;           // ← CORRECT FIELD
                      dailyRevenue[key] = dailyRevenue[key]! + (amount?.toDouble() ?? 0.0);
                    }
                  }

                  final spots = dailyRevenue.entries.map((e) => FlSpot(days.indexOf(e.key).toDouble(), e.value)).toList();

                  return LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) => Text(DateFormat('EEE').format(days[v.toInt()]), style: const TextStyle(fontSize: 11)),
                        )),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 0, maxX: 6, minY: 0,
                      lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.green, barWidth: 4, dotData: FlDotData(show: true))],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Payment Methods – Only Delivered Orders + Only COD & GCash
class _PaymentMethodPieChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Payment Methods", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: StreamBuilder<QuerySnapshot>(
                // Only fetch Delivered orders
                stream: firestore
                    .collection('orders')
                    .where('deliveryStatus', isEqualTo: 'Delivered')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("No delivered orders yet", style: TextStyle(fontSize: 16)));
                  }

                  int cod = 0;
                  int gcash = 0;

                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final method = data['paymentMethod']?.toString().toLowerCase();

                    if (method == 'cod') cod++;
                    else if (method == 'gcash') gcash++;
                  }

                  final total = cod + gcash;
                  if (total == 0) {
                    return const Center(child: Text("No COD/GCash payments in delivered orders", style: TextStyle(fontSize: 15)));
                  }

                  return PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          value: cod.toDouble(),
                          title: "COD\n$cod",
                          color: Colors.orange.shade600,
                          radius: 70,
                          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        PieChartSectionData(
                          value: gcash.toDouble(),
                          title: "GCash\n$gcash",
                          color: Colors.blue.shade600,
                          radius: 70,
                          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                      centerSpaceRadius: 40,
                      sectionsSpace: 4,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _FullWidthStatCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Stream<QuerySnapshot> stream;
  final String Function(QuerySnapshot) valueBuilder;

  const _FullWidthStatCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.stream,
    required this.valueBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            final value = snapshot.hasData ? valueBuilder(snapshot.data!) : '...';

            return Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: color.withOpacity(0.2),
                  child: Icon(icon, size: 36, color: color),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Top Products & Live Stat Card – unchanged & safe
// ... (same as previous version – already safe and using correct structure)

class _LiveStatCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Stream<QuerySnapshot> stream;
  final String Function(QuerySnapshot) valueBuilder;

  const _LiveStatCard({required this.title, required this.icon, required this.color, required this.stream, required this.valueBuilder});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              final value = snapshot.hasData ? valueBuilder(snapshot.data!) : '...';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 32, color: color),
                  const SizedBox(height: 12),
                  Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(title, style: TextStyle(color: Colors.grey[600])),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Top Selling Products", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Delivered').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();

                final Map<String, int> sales = {};
                for (var doc in snapshot.data!.docs) {
                  final items = (doc.data() as Map)['items'] as List<dynamic>? ?? [];
                  for (var item in items) {
                    final name = item['name']?.toString() ?? 'Unknown';
                    final qty = (item['quantity'] as num?)?.toInt() ?? 0;
                    sales[name] = (sales[name] ?? 0) + qty;
                  }
                }

                final top5 = sales.entries.toList()..sort((a, b) => b.value.compareTo(a.value))..take(5);

                return Column(
                  children: top5.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500))),
                        Text("${e.value} sold", style: const TextStyle(color: Colors.black54)),
                      ],
                    ),
                  )).toList(),
                );
              },
            ),
          ],
        ),
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