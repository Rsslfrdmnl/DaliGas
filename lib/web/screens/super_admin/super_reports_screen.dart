import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/main_web.dart';
import 'admin_welcome_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_sales_screen.dart';
import 'super_inventory_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_settings_screen.dart';

final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

class SuperReportsScreen extends StatefulWidget {
  const SuperReportsScreen({super.key});
  @override
  State<SuperReportsScreen> createState() => _SuperReportsScreenState();
}

class _SuperReportsScreenState extends State<SuperReportsScreen> {
  DateTimeRange? _selectedRange;
  String _selectedReportType = "All";
  int _currentPage = 0;
  final int _itemsPerPage = 4;

  Future<void> _logout(BuildContext context) async {
  await FirebaseAuth.instance.signOut();

  if (!context.mounted) {
    return;
  }

  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
}

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _selectedRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (picked != null) setState(() => _selectedRange = picked);
  }

  Future<void> _generateReport() async {
    if (_selectedRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a date range first")),
      );
      return;
    }

    final start = Timestamp.fromDate(_selectedRange!.start);
    final end = Timestamp.fromDate(_selectedRange!.end.add(const Duration(days: 1)));

    final ordersSnap = await firestore
        .collection('orders')
        .where('deliveryStatus', isEqualTo: 'Delivered')
        .get();

    double totalSales = 0.0;
    int deliveredOrders = 0;

    for (var doc in ordersSnap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) continue;
      final createdDate = createdAt.toDate();

      final inRange = createdDate.isAfter(_selectedRange!.start.subtract(const Duration(days: 1))) &&
                      createdDate.isBefore(_selectedRange!.end.add(const Duration(days: 1)));

      if (inRange) {
        final totalRaw = data['total'];
        final total = totalRaw is num ? totalRaw.toDouble() : 0.0;
        totalSales += total;
        deliveredOrders++;
      }
    }

    final reportId = "RPT${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}";
    final typeText = _selectedReportType == "All" ? "Business Summary" : _selectedReportType;
    final title = "$typeText • ${currency.format(totalSales)} • ${DateFormat('MMM d, yyyy').format(_selectedRange!.start)} – ${DateFormat('MMM d, yyyy').format(_selectedRange!.end)}";

    await firestore.collection('business_reports').add({
      'reportId': reportId,
      'type': typeText,
      'title': title,
      'generatedAt': FieldValue.serverTimestamp(),
      'startDate': start,
      'endDate': end,
      'totalSales': totalSales,
      'totalOrders': deliveredOrders,
      'generatedBy': FirebaseAuth.instance.currentUser?.email ?? 'superadmin',
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Report generated successfully!"), backgroundColor: Colors.green),
    );
    setState(() => _currentPage = 0);
  }

  void _exportReports() async {
    final snap = await firestore.collection('business_reports').orderBy('generatedAt', descending: true).get();
    final rows = [['Report ID', 'Type', 'Title', 'Generated On', 'Sales', 'Orders']];

    for (var doc in snap.docs) {
      final d = doc.data();
      final date = (d['generatedAt'] as Timestamp?)?.toDate();
      rows.add([
        d['reportId'] ?? '',
        d['type'] ?? '',
        d['title'] ?? '',
        date != null ? DateFormat('MMM d, yyyy • hh:mm a').format(date) : '',
        currency.format((d['totalSales'] as num?)?.toDouble() ?? 0),
        (d['totalOrders'] ?? 0).toString(),
      ]);
    }

    final csv = rows.map((r) => r.map((c) => '"${c.toString().replaceAll('"', '""')}"').join(',')).join('\r\n');
    final blob = html.Blob([utf8.encode(csv)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'dali_gas_reports_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final start = _selectedRange?.start ?? DateTime(2020, 1, 1);
    final end = (_selectedRange?.end ?? DateTime.now()).add(const Duration(days: 1));

    return Scaffold(
      body: Row(
        children: [
          // Sidebar (your existing one)
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
              _SidebarItem(Icons.dashboard, "Dashboard", false, () {
                Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperAdminDashboard(), transitionDuration: Duration.zero));
              }),
              _SidebarItem(Icons.bar_chart, "Sales", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperSalesScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.inventory, "Inventory", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperInventoryScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.people, "Employees", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperEmployeesScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.feedback, "Feedbacks", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperFeedbacksScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.assignment, "Business Reports", true, () {}),
              _SidebarItem(Icons.settings, "Settings", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperSettingsScreen(), transitionDuration: Duration.zero))),
              const Spacer(),
              _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
              const SizedBox(height: 20),
            ]),
          ),

          // Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Business Reports", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // LIVE SUMMARY CARDS
                StreamBuilder<QuerySnapshot>(
                  stream: firestore.collection('orders').where('deliveryStatus', isEqualTo: 'Delivered').snapshots(),
                  builder: (context, orderSnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: firestore.collection('business_reports').snapshots(),
                      builder: (context, reportSnapshot) {
                        double sales = 0.0;
                        int deliveredOrders = 0;
                        int reportsCount = 0;

                        if (orderSnapshot.hasData) {
                          for (var doc in orderSnapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>?;
                            if (data == null) continue;

                            final createdAt = data['createdAt'] as Timestamp?;
                            if (createdAt == null) continue;
                            final createdDate = createdAt.toDate();

                            final inRange = _selectedRange == null ||
                                (createdDate.isAfter(_selectedRange!.start.subtract(const Duration(days: 1))) &&
                                 createdDate.isBefore(_selectedRange!.end.add(const Duration(days: 1))));

                            if (inRange) {
                              final totalRaw = data['total'];
                              final total = totalRaw is num ? totalRaw.toDouble() : 0.0;
                              sales += total;
                              deliveredOrders++;
                            }
                          }
                        }

                        if (reportSnapshot.hasData) {
                          reportsCount = reportSnapshot.data!.size;
                        }

                        return Row(
                          children: [
                            _statCard(Icons.attach_money, currency.format(sales), "Total Sales"),
                            _statCard(Icons.account_balance_wallet, currency.format(sales), "Net Revenue"),
                            _statCard(Icons.local_shipping, deliveredOrders.toString(), "Delivered Orders"),
                            _statCard(Icons.bar_chart, reportsCount.toString(), "Reports Generated"),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 30),

                // FILTERS + ACTIONS
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    ElevatedButton.icon(
                      onPressed: _pickDateRange,
                      icon: const Icon(Icons.date_range, color: Colors.white),
                      label: Text(_selectedRange == null ? "All Time" : "${DateFormat('MMM d').format(_selectedRange!.start)} - ${DateFormat('MMM d, yyyy').format(_selectedRange!.end)}", style: const TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D2236), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<String>(
                        value: _selectedReportType,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        items: const [
                          DropdownMenuItem(value: "All", child: Text("All Reports")),
                          DropdownMenuItem(value: "Business Summary", child: Text("Business Summary")),
                          DropdownMenuItem(value: "Sales", child: Text("Sales Report")),
                          DropdownMenuItem(value: "Orders", child: Text("Orders Report")),
                        ],
                        onChanged: (v) => v != null ? setState(() => {_selectedReportType = v, _currentPage = 0}) : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _generateReport,
                      icon: const Icon(Icons.add_chart, color: Colors.white),
                      label: const Text("Generate", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                    ),
                  ]),
                  ElevatedButton.icon(
                    onPressed: _exportReports,
                    icon: const Icon(Icons.download, color: Colors.white),
                    label: const Text("Export All", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                  ),
                ]),
                const SizedBox(height: 20),

                // REPORTS TABLE WITH PAGINATION
                Expanded(
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: firestore.collection('business_reports').orderBy('generatedAt', descending: true).snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                                var docs = snapshot.data!.docs;
                                if (_selectedReportType != "All") {
                                  docs = docs.where((doc) => (doc['type'] as String?) == _selectedReportType).toList();
                                }

                                final totalItems = docs.length;
                                final totalPages = (totalItems / _itemsPerPage).ceil();
                                final startIndex = _currentPage * _itemsPerPage;
                                final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
                                final pageDocs = docs.sublist(startIndex, endIndex);

                                return Column(
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        child: LayoutBuilder(
                                          builder: (context, constraints) => ConstrainedBox(
                                            constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                            child: DataTable(
                                              headingRowHeight: 60,
                                              dataRowHeight: 72,
                                              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                              columnSpacing: 60,
                                              columns: const [
                                                DataColumn(label: Text("Report ID", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Type", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Title", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Generated On", style: TextStyle(fontWeight: FontWeight.w600))),
                                                DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.w600))),
                                              ],
                                              rows: pageDocs.map((doc) {
                                                final d = doc.data() as Map<String, dynamic>;
                                                final date = (d['generatedAt'] as Timestamp?)?.toDate();
                                                return DataRow(cells: [
                                                  DataCell(Text(d['reportId'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D2236)))),
                                                  DataCell(Text(d['type'] ?? '')),
                                                  DataCell(Text(d['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis)),
                                                  DataCell(Text(date != null ? DateFormat('MMM d, yyyy • hh:mm a').format(date) : '')),
                                                  DataCell(Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                                    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(30)),
                                                    child: const Text("Generated", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                                  )),
                                                ]);
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // PAGINATOR
                                    if (totalItems > _itemsPerPage)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            IconButton(
                                              onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                                              icon: const Icon(Icons.chevron_left),
                                            ),
                                            ...List.generate(totalPages, (i) => Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4),
                                              child: InkWell(
                                                onTap: () => setState(() => _currentPage = i),
                                                child: Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: _currentPage == i ? const Color(0xFF0D2236) : Colors.grey.shade200,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Text("${i + 1}", style: TextStyle(color: _currentPage == i ? Colors.white : Colors.black)),
                                                ),
                                              ),
                                            )),
                                            IconButton(
                                              onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                                              icon: const Icon(Icons.chevron_right),
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
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label) {
    return Expanded(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Icon(icon, size: 40, color: const Color(0xFF0D2236)),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF0D2236))),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 15, color: Colors.grey)),
          ]),
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