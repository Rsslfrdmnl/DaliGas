import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'package:daligas/web/main_web.dart';
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
  // REMOVED: StreamSubscription list & dispose() → causes crash on Web
  // ← These two lines were the only culprits left

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
                child: Image.asset("assets/images/daligas_logo.png", height: 80),
              ),
              Transform.translate(
                offset: const Offset(-22, 0),
                child: const Text(
                  "DALI GAS",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          _SidebarItem(Icons.dashboard, "Dashboard", true, () {}),
          _SidebarItem(Icons.shopping_cart, "Orders", false, () {
            _navigateTo(const AdminOrdersScreen());
          }),
          _SidebarItem(Icons.inventory, "Inventory", false, () {
            _navigateTo(const AdminInventoryScreen());
          }),
          _SidebarItem(Icons.local_shipping, "Delivery Management", false, () {
            _navigateTo(const AdminDeliveryScreen());
          }),
          _SidebarItem(Icons.feedback, "Feedback", false, () {
            _navigateTo(const AdminFeedbackScreen());
          }),
          _SidebarItem(Icons.flag, "User Reports", false, () {
            _navigateTo(const AdminReportsScreen());
          }),
          _SidebarItem(Icons.settings, "Settings", false, () {
            _navigateTo(const AdminSettingsScreen());
          }),

          const Spacer(),
          _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _navigateTo(Widget page) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
      ),
    );
  }

  // ENHANCED: Supports client-side filtering (needed for "Today" count)
  Widget _buildLiveStatCard({
    required String title,
    required IconData icon,
    required Color color,
    required Stream<QuerySnapshot> stream,
    String Function(AsyncSnapshot<QuerySnapshot>)? builderOverride,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        String value = '...';

        if (snapshot.hasError) {
          value = 'Error';
        } else if (snapshot.hasData) {
          if (builderOverride != null) {
            value = builderOverride(snapshot);
          } else {
            value = snapshot.data!.docs.length.toString();
          }
        }

        return _buildStatCard(title, value, icon, color);
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
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.black54)),
              ],
            ),
          ],
        ),
      ),
    );
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
          _buildSidebar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Welcome, Sub Admin",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  // ROW 1: New Orders + Deliveries in Progress
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildLiveStatCard(
                          title: "New Orders",
                          icon: Icons.shopping_cart,
                          color: Colors.blue,
                          stream: firestore
                              .collection('orders')
                              .where('deliveryStatus', isEqualTo: 'Processing')
                              .snapshots(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildLiveStatCard(
                          title: "Deliveries in Progress",
                          icon: Icons.local_shipping,
                          color: Colors.green,
                          stream: firestore
                              .collection('orders')
                              .where('deliveryStatus', isEqualTo: 'Shipped')
                              .snapshots(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ROW 2: Low Stock + Completed Today (FIXED!)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildLiveStatCard(
                          title: "Inventory Low Stock",
                          icon: Icons.inventory,
                          color: Colors.orange,
                          stream: firestore
                              .collection('products')
                              .where('stocks', isLessThanOrEqualTo: 5)
                              .snapshots(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildLiveStatCard(
                          title: "Completed Deliveries Today",
                          icon: Icons.check_circle,
                          color: Colors.teal,
                          stream: firestore
                              .collection('orders')
                              .where('deliveryStatus', isEqualTo: 'Delivered')
                              .snapshots(),
                          builderOverride: (snapshot) {
                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return '0';

                            final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
                            int count = 0;

                            for (var doc in snapshot.data!.docs) {
                              final data = doc.data() as Map<String, dynamic>?;
                              if (data == null) continue;

                              // 100% SAFE ON WEB: Check if field exists first
                              if (data.containsKey('deliveredAt') && data['deliveredAt'] is Timestamp) {
                                final date = (data['deliveredAt'] as Timestamp).toDate();
                                if (date.year == today.year &&
                                    date.month == today.month &&
                                    date.day == today.day) {
                                  count++;
                                }
                              }
                            }

                            return count.toString();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Charts (will be upgraded next)
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

    Widget _buildOrdersChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Orders Trend (Last 7 Days)",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: firestore.collection('orders').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.blue));
                  }

                  final now = DateTime.now();
                  final last7Days = List.generate(7, (i) => DateTime(now.year, now.month, now.day - (6 - i)));

                  final Map<DateTime, int> dailyCount = {for (var day in last7Days) DateTime(day.year, day.month, day.day): 0};

                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>?;
                    if (data?.containsKey('createdAt') != true) continue;
                    final date = (data!['createdAt'] as Timestamp).toDate();
                    final key = DateTime(date.year, date.month, date.day);
                    if (dailyCount.containsKey(key)) dailyCount[key] = dailyCount[key]! + 1;
                  }

                  final spots = dailyCount.entries.map((e) {
                    final index = last7Days.indexWhere((d) => d.year == e.key.year && d.month == e.key.month && d.day == e.key.day);
                    return FlSpot(index.toDouble(), e.value.toDouble());
                  }).toList();

                  return LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: 5,
                        getDrawingHorizontalLine: (_) => const FlLine(color: Colors.black12, strokeWidth: 1),
                        getDrawingVerticalLine: (_) => const FlLine(color: Colors.black12, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final date = last7Days[value.toInt()];
                              final isToday = date.day == now.day;
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(
                                  '${date.month}/${date.day}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                                    color: isToday ? Colors.blue : Colors.black54,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          barWidth: 5,
                          color: Colors.blue,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                              radius: 6,
                              color: Colors.white,
                              strokeWidth: 3,
                              strokeColor: Colors.blue,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [Colors.blue.withOpacity(0.4), Colors.blue.withOpacity(0.0)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          tooltipRoundedRadius: 12,
                          tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          tooltipMargin: 12,
                          getTooltipColor: (_) => Colors.blue.shade700,
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              final date = last7Days[spot.x.toInt()];
                              return LineTooltipItem(
                                '${date.day}/${date.month}\n${spot.y.toInt()} orders',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeInOutCubic,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildDeliveryChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Delivery Performance",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 32),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: firestore.collection('orders').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.blue));
                  }

                  final Map<String, int> count = {
                    'Processing': 0,
                    'Shipped': 0,
                    'Delivered': 0,
                    'Cancelled': 0,
                  };

                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>?;
                    final status = data?['deliveryStatus'] as String?;
                    if (status != null && count.containsKey(status)) {
                      count[status] = count[status]! + 1;
                    }
                  }

                  final total = count.values.reduce((a, b) => a + b);
                  if (total == 0) {
                    return const Center(
                      child: Text("No orders yet", style: TextStyle(fontSize: 16, color: Colors.black54)),
                    );
                  }

                  final entries = count.entries.where((e) => e.value > 0).toList();

                  return Column(
                    children: entries.map((entry) {
                      final percentage = (entry.value / total) * 100;
                      final color = switch (entry.key) {
                        'Processing' => Colors.orange.shade600,
                        'Shipped' => Colors.blue.shade600,
                        'Delivered' => Colors.green.shade600,
                        'Cancelled' => Colors.red.shade600,
                        _ => Colors.grey,
                      };

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                const Spacer(),
                                Text(
                                  "${entry.value} orders • ${percentage.toStringAsFixed(0)}%",
                                  style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black54),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: percentage / 100,
                                backgroundColor: Colors.grey.shade200,
                                color: color,
                                minHeight: 28,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool active;
  final VoidCallback onTap;

  const _SidebarItem(this.icon, this.title, this.active, this.onTap, {Key? key}) : super(key: key);

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