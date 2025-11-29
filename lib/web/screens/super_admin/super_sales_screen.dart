// lib/web/screens/super_admin/super_sales_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:daligas/web/main_web.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_inventory_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

class SuperSalesScreen extends StatefulWidget {
  const SuperSalesScreen({super.key});
  @override State<SuperSalesScreen> createState() => _SuperSalesScreenState();
}

class _SuperSalesScreenState extends State<SuperSalesScreen> {
  final NumberFormat currency = NumberFormat.currency(locale: 'fil_PH', symbol: '₱');
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 0;
  final int _itemsPerPage = 1;

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminWelcomeScreen()));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

    @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar — unchanged
          Container(
            width: 220,
            color: const Color(0xFF0D2236),
            child: Column(children: [
              const SizedBox(height: 40),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Transform.translate(offset: const Offset(-10, 0), child: Image.asset("assets/images/daligas_logo.png", height: 80)),
                Transform.translate(offset: const Offset(-22, 0), child: const Text("DALI GAS", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white))),
              ]),
              const SizedBox(height: 30),
              _SidebarItem(Icons.dashboard, "Dashboard", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperAdminDashboard(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.bar_chart, "Sales", true, () {}),
              _SidebarItem(Icons.inventory, "Inventory", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperInventoryScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.people, "Employees", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperEmployeesScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.feedback, "Feedbacks", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperFeedbacksScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.assignment, "Reports", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperReportsScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.settings, "Settings", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperSettingsScreen(), transitionDuration: Duration.zero))),
              const Spacer(),
              _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
            ]),
          ),

          // Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Sales", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // Top Stats
                  Row(children: [
                    Expanded(child: _LiveSalesStat(title: "Total Revenue", color: Colors.green, stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Delivered').snapshots(), valueBuilder: (snap) {
                      double sum = 0;
                      for (var doc in snap.docs) sum += ((doc.data() as Map)['total'] as num?)?.toDouble() ?? 0;
                      return currency.format(sum);
                    })),
                    const SizedBox(width: 16),
                    Expanded(child: _LiveSalesStat(title: "Total Delivered Orders", color: Colors.blue, stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Delivered').snapshots(), valueBuilder: (snap) => snap.docs.length.toString())),
                    const SizedBox(width: 16),
                    Expanded(child: _LiveSalesStat(title: "Average Order Value", color: Colors.purple, stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Delivered').snapshots(), valueBuilder: (snap) {
                      if (snap.docs.isEmpty) return "₱0";
                      double sum = 0;
                      for (var doc in snap.docs) sum += ((doc.data() as Map)['total'] as num?)?.toDouble() ?? 0;
                      return currency.format(sum / snap.docs.length);
                    })),
                  ]),
                  const SizedBox(height: 28),

                  // Charts — compact
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 2, child: SizedBox(height: 220, child: _SalesLineChart())),
                    const SizedBox(width: 20),
                    Expanded(child: SizedBox(height: 220, child: _PaymentPieChart())),
                  ]),
                  const SizedBox(height: 32),

                  // Table Card — EXACTLY like AdminOrdersScreen
                  Expanded(
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Search Bar — inside card, just like AdminOrdersScreen
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) {
                                  setState(() {
                                    _searchQuery = val.toLowerCase();
                                    _currentPage = 0;
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: "Search by Transaction ID, Customer, or Product",
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                              ),
                            ),

                            // Table + Paginator
                            Expanded(
  child: StreamBuilder<QuerySnapshot>(
    stream: firestore.collection('orders').orderBy('createdAt', descending: true).snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      // Filter logic
      final filtered = snapshot.data!.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final orderId = doc.id.toString().toLowerCase();
        final userId = (data['userId'] as String?)?.toLowerCase() ?? '';
        final items = data['items'] as List<dynamic>? ?? [];
        final productNames = items.map((i) => (i['name'] as String?)?.toLowerCase() ?? '').join(' ');
        final searchable = '$orderId $userId $productNames';
        return _searchQuery.isEmpty || searchable.contains(_searchQuery);
      }).toList();

      final totalPages = (filtered.length / _itemsPerPage).ceil();
      final start = _currentPage * _itemsPerPage;
      final end = (start + _itemsPerPage).clamp(0, filtered.length);
      final pageItems = filtered.sublist(start, end);

      return Column(
        children: [
          // ───── TABLE THAT FULLY STRETCHES ─────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowHeight: 56,
                      dataRowHeight: 70,
                      headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                      dividerThickness: 0,
                      columnSpacing: 20,
                      horizontalMargin: 24,
                      border: TableBorder.all(
                        color: Colors.grey.shade300,
                        width: 1,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      columns: const [
                        DataColumn(label: Text('Transaction ID', style: TextStyle(fontWeight: FontWeight.w600))),
                        DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.w600))),
                        DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600))),
                        DataColumn(label: Text('Product', style: TextStyle(fontWeight: FontWeight.w600))),
                        DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.w600))),
                        DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.w600))),
                        DataColumn(label: Text('Payment', style: TextStyle(fontWeight: FontWeight.w600))),
                        DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600))),
                      ],
                      rows: pageItems.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final items = (data['items'] as List?) ?? [];
                        final firstItem = items.isNotEmpty ? items[0] as Map<String, dynamic> : null;
                        final status = (data['deliveryStatus'] as String?) ?? 'Processing';

                        Color statusColor = Colors.orange;
                        if (status == 'Delivered') statusColor = Colors.green;
                        if (status == 'Cancelled') statusColor = Colors.red;
                        if (status == 'Shipped') statusColor = Colors.blue;

                        return DataRow(cells: [
                          DataCell(Text(doc.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                          DataCell(Text(
                            data['createdAt'] != null
                                ? DateFormat('MMM dd, yyyy').format((data['createdAt'] as Timestamp).toDate())
                                : '-',
                          )),
                          DataCell(FutureBuilder<DocumentSnapshot>(
                            future: firestore.collection('users').doc(data['userId']).get(),
                            builder: (context, snap) {
                              final name = (!snap.hasData || !snap.data!.exists)
    ? '...'
    : (snap.data!.data() as Map<String, dynamic>?)?['fullName'] ?? 'Unknown';
                              return Text(name);
                            },
                          )),
                          DataCell(Text(firstItem?['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
                          DataCell(Text(firstItem?['quantity']?.toString() ?? '-', textAlign: TextAlign.center)),
                          DataCell(Text(
                            currency.format((data['total'] as num?)?.toDouble() ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                          )),
                          DataCell(Text(
                            (data['paymentMethod'] as String?)?.toUpperCase() ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          )),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),

          // ───── PAGINATOR ─────
          if (totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                    icon: const Icon(Icons.chevron_left),
                    disabledColor: Colors.grey,
                  ),
                  const SizedBox(width: 20),
                  Text(
                    "Page ${_currentPage + 1} of $totalPages",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                    icon: const Icon(Icons.chevron_right),
                    disabledColor: Colors.grey,
                  ),
                ],
              ),
            ),
        ],
      );
    },
  ),
),
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

// ───── Live Stat Card ─────
class _LiveSalesStat extends StatelessWidget {
  final String title; final Color color; final Stream<QuerySnapshot> stream; final String Function(QuerySnapshot) valueBuilder;
  const _LiveSalesStat({required this.title, required this.color, required this.stream, required this.valueBuilder});

  @override Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            final value = snapshot.hasData ? valueBuilder(snapshot.data!) : '...';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, color: Colors.black54)),
                const SizedBox(height: 8),
                Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ───── Smaller Charts (220px) ─────
class _SalesLineChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Revenue Last 7 Days", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Delivered').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  final now = DateTime.now();
                  final days = List.generate(7, (i) => DateTime(now.year, now.month, now.day - (6 - i)));
                  final revenue = List<double>.filled(7, 0.0); // Fixed-size list

                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final deliveredAt = data['deliveredAt'] as Timestamp?;
                    if (deliveredAt == null) continue;

                    final date = deliveredAt.toDate();
                    final dayKey = DateTime(date.year, date.month, date.day);

                    // Find index safely within last 7 days
                    final index = days.indexWhere((d) => 
                      d.year == dayKey.year && d.month == dayKey.month && d.day == dayKey.day
                    );

                    if (index != -1) {
                      revenue[index] += ((data['total'] as num?)?.toDouble() ?? 0);
                    }
                  }

                  final spots = revenue
                      .asMap()
                      .entries
                      .map((e) => FlSpot(e.key.toDouble(), e.value))
                      .toList();

                  return LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= days.length) return const SizedBox();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(DateFormat('EEE').format(days[index]), style: const TextStyle(fontSize: 10)),
                              );
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: Colors.green,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                        ),
                      ],
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

class _PaymentPieChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Payment Methods",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: firestore
                    .collection('orders')
                    .where('deliveryStatus', isEqualTo: 'Delivered')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  int cod = 0, gcash = 0;
                  for (var doc in snapshot.data!.docs) {
                    final method = (doc.data() as Map<String, dynamic>)['paymentMethod']
                        ?.toString()
                        .toLowerCase();
                    if (method == 'cod') cod++;
                    else if (method == 'gcash') gcash++;
                  }

                  if (cod + gcash == 0) {
                    return const Center(
                      child: Text("No delivered orders", style: TextStyle(color: Colors.grey)),
                    );
                  }

                  return PieChart(
                    PieChartData(
                      centerSpaceRadius: 30,
                      sectionsSpace: 4,
                      sections: [
                        PieChartSectionData(
                          value: cod.toDouble(),
                          color: Colors.orange.shade600,
                          title: "COD\n$cod",
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          value: gcash.toDouble(),
                          color: Colors.blue.shade700,
                          title: "GCash\n$gcash",
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
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

// ───── Final Transaction Table – 5 rows, full width, smart paginator ─────
class _TransactionTable extends StatelessWidget {
  final String searchQuery;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  const _TransactionTable({required this.searchQuery, required this.currentPage, required this.onPageChanged});

  static final NumberFormat currency = NumberFormat.currency(locale: 'fil_PH', symbol: '₱');
  final int rowsPerPage = 5;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      child: StreamBuilder<QuerySnapshot>(
        stream: firestore.collection('orders').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var filtered = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final orderId = doc.id.toLowerCase();
            final userId = (data['userId'] as String?)?.toLowerCase() ?? '';
            final items = data['items'] as List<dynamic>? ?? [];
            final searchable = [orderId, userId, ...items.map((i) => (i['name'] as String?)?.toLowerCase() ?? '')].join(' ');
            return searchQuery.isEmpty || searchable.contains(searchQuery);
          }).toList();

          final totalPages = (filtered.length / rowsPerPage).ceil();
          final start = currentPage * rowsPerPage;
          final pageData = filtered.length > start ? filtered.sublist(start, (start + rowsPerPage).clamp(0, filtered.length)) : <QueryDocumentSnapshot>[];

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 1000),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                      dataRowHeight: 68,
                      headingRowHeight: 56,
                      columnSpacing: 24,
                      columns: const [
                        DataColumn(label: Text("Transaction ID", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Date", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Customer", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Product", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Qty", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Amount", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Payment", style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: pageData.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final items = (data['items'] as List?) ?? [];
                        final firstItem = items.isNotEmpty ? items[0] as Map<String, dynamic> : null;
                        final status = (data['deliveryStatus'] as String?) ?? 'Unknown';

                        Color statusColor = Colors.grey;
                        if (status == 'Delivered') statusColor = Colors.green;
                        else if (status == 'Cancelled') statusColor = Colors.red;
                        else if (status == 'Processing') statusColor = Colors.orange;
                        else if (status == 'Shipped') statusColor = Colors.blue;

                        return DataRow(cells: [
                          DataCell(Text(doc.id, style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(data['createdAt'] != null ? DateFormat('MMM dd, yyyy').format((data['createdAt'] as Timestamp).toDate()) : '-')),
                          DataCell(FutureBuilder<DocumentSnapshot>(
                            future: firestore.collection('users').doc(data['userId'] as String?).get(),
                            builder: (context, snap) {
                              if (!snap.hasData || snap.data == null) return const Text('...');
                              final name = (snap.data!.data() as Map<String, dynamic>?)?['fullName'] ?? 'Unknown User';
                              return Text(name);
                            },
                          )),
                          DataCell(Text(firstItem?['name'] ?? '-')),
                          DataCell(Text(firstItem?['quantity']?.toString() ?? '-')),
                          DataCell(Text(currency.format((data['total'] as num?)?.toDouble() ?? 0))),
                          DataCell(Text(data['paymentMethod']?.toString() ?? '-')),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                            child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),

              // Clean Paginator – Max 5 pages shown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null, icon: const Icon(Icons.chevron_left)),
                    ...List.generate(
                      totalPages.clamp(0, 5),
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () => onPageChanged(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: i == currentPage ? Colors.blue.shade600 : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text("${i + 1}", style: TextStyle(color: i == currentPage ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),
                    if (totalPages > 5) const Text(" ... "),
                    IconButton(onPressed: currentPage < totalPages - 1 ? () => onPageChanged(currentPage + 1) : null, icon: const Icon(Icons.chevron_right)),
                  ],
                ),
              ),
            ],
          );
        },
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