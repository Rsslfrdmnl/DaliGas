import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'package:daligas/web/main_web.dart';
import 'admin_dashboard_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_feedbacks_screen.dart';
import 'admin_settings_screen.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  DateTimeRange? selectedDateRange;
  String selectedReportType = "All";
  int _currentPage = 0;
  final int _pageSize = 6;

  void _exportReportsToCsv() async {
  try {
    // Fetch all reports
    final reportsSnapshot = await firestore.collection('reports').get();

    final rows = <List<String>>[];

    // Add header row
    rows.add([
      'Report ID',
      'Type',
      'Reporter Name',
      'Reported User',
      'Reason',
      'Content',
      'Status',
      'Date Submitted'
    ]);

    for (var doc in reportsSnapshot.docs) {
      final data = doc.data();
      final reportId = doc.id;
      final type = data['type']?.toString() ?? 'Others';
      final reporterName = data['reporterName']?.toString() ?? 'Unknown';
      final reportedUserName = data['reportedUserName']?.toString() ?? '';
      final reason = data['reason']?.toString() ?? '';
      final content = data['content']?.toString() ?? '';
      final status = (data['status'] ?? 'pending').toString();
      final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

      rows.add([
        reportId,
        type,
        reporterName,
        reportedUserName,
        reason,
        content,
        status,
        DateFormat('MMMM d, yyyy - hh:mm a').format(timestamp),
      ]);
    }

    // Convert to CSV string
    final csvString = _simpleCsvConvert(rows);

    // Create and download the file
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final blob = html.Blob([utf8.encode(csvString)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'reports_export_$timestamp.csv')
      ..click();

    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reports exported successfully (${rows.length - 1} reports)'),
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error exporting reports: $e')),
    );
  }
}

// Add this helper method for CSV conversion
String _simpleCsvConvert(List<List<String>> rows) {
  String escapeCell(String cell) {
    if (cell.contains('"')) cell = cell.replaceAll('"', '""');
    if (cell.contains(',') || cell.contains('"') || cell.contains('\n')) {
      return '"$cell"';
    }
    return cell;
  }

  return rows.map((row) => row.map(escapeCell).join(',')).join('\r\n');
}

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminWelcomeScreen()));
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
                child: const Text("DALI GAS",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 30),
          _SidebarItem(Icons.dashboard, "Dashboard", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminDashboardScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.shopping_cart, "Orders", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminOrdersScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.inventory, "Inventory", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminInventoryScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.local_shipping, "Delivery Management", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminDeliveryScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.feedback, "Feedback", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminFeedbackScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.flag, "User Reports", true, () {}),
          _SidebarItem(Icons.settings, "Settings", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminSettingsScreen(), transitionDuration: Duration.zero))),
          const Spacer(),
          _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String title) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 36, color: const Color(0xFF0D2236)),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeChip(String type) {
    final color = switch (type.toLowerCase()) {
      "comment" || "comments" => Colors.blue.shade100,
      "reply" => Colors.cyan.shade100,
      "chat" => Colors.orange.shade100,
      "review" || "reviews" => Colors.purple.shade100,
      "bug" => Colors.red.shade100,
      "order issue" => Colors.teal.shade100,
      "payment problem" => Colors.deepOrange.shade100,
      "delivery" => Colors.indigo.shade100,
      "others" || _ => Colors.grey.shade300,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(type, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D2236))),
    );
  }

  Color _reasonColor(String reason) {
    final lower = reason.toLowerCase();
    if (lower.contains("rude") || lower.contains("harassment") || lower.contains("offensive")) return Colors.red.shade600;
    if (lower.contains("fake")) return Colors.orange.shade700;
    if (lower.contains("scam") || lower.contains("fraud")) return Colors.purple.shade700;
    if (lower.contains("technical") || lower.contains("bug")) return Colors.blue.shade700;
    return Colors.grey.shade700;
  }

  void _showReportDetails(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final dateStr = timestamp != null ? DateFormat('MMMM d, yyyy • h:mm a').format(timestamp) : '—';
    final status = (data['status'] ?? 'pending').toString().toLowerCase();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.flag, color: Colors.red),
            const SizedBox(width: 10),
            Text("Report #${doc.id}", style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow("Type", _typeChip(data['type'] ?? 'Others')),
                const Divider(height: 30),
                _detailRow("Reporter", data['reporterName'] ?? 'Unknown'),
                _detailRow("Reported User", data['reportedUserName'] ?? '—'),
                _detailRow("Date Submitted", dateStr),
                _detailRow("Reason", data['reason'] ?? '—'),
                const SizedBox(height: 16),
                const Text("Report Content:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFFF9F6FB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    data['content'] ?? 'No content provided.',
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (status == 'pending') ...[
            TextButton.icon(
              onPressed: () async {
                await firestore.collection('reports').doc(doc.id).update({
                  'status': 'dismissed',
                  'dismissedAt': FieldValue.serverTimestamp(),
                  'dismissedBy': FirebaseAuth.instance.currentUser?.uid,
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Report dismissed"), backgroundColor: Colors.orange),
                );
              },
              icon: const Icon(Icons.cancel, color: Colors.orange),
              label: const Text("Dismiss"),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await firestore.collection('reports').doc(doc.id).update({
                  'status': 'resolved',
                  'resolvedAt': FieldValue.serverTimestamp(),
                  'resolvedBy': FirebaseAuth.instance.currentUser?.uid,
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Report resolved successfully!"), backgroundColor: Colors.green),
                );
              },
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text("Resolve"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ] else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text("$label:", style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: value is Widget ? value : Text(value.toString())),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Reports Management", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('reports').snapshots(),
                    builder: (context, snapshot) {
                      int total = 0, pending = 0, resolved = 0, dismissed = 0;
                      if (snapshot.hasData && snapshot.data != null) {
                        final docs = snapshot.data!.docs;
                        total = docs.length;
                        for (var doc in docs) {
                          final status = (doc['status'] as String?)?.toLowerCase() ?? 'pending';
                          if (status == 'pending') pending++;
                          else if (status == 'resolved') resolved++;
                          else if (status == 'dismissed') dismissed++;
                        }
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatCard(Icons.flag, total.toString(), "Total Reports"),
                          _buildStatCard(Icons.warning_amber, pending.toString(), "Pending Reports"),
                          _buildStatCard(Icons.check_circle, resolved.toString(), "Resolved"),
                          _buildStatCard(Icons.cancel, dismissed.toString(), "Dismissed"),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 30),

                  Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Row(
      children: [
        ElevatedButton.icon(
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 1),
              initialDateRange: selectedDateRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
            );
            if (picked != null) setState(() => selectedDateRange = picked);
          },
          icon: const Icon(Icons.date_range, color: Colors.white),
          label: Text(
            selectedDateRange == null
                ? "Select Date Range"
                : "${DateFormat('MMM d').format(selectedDateRange!.start)} - ${DateFormat('MMM d, yyyy').format(selectedDateRange!.end)}",
            style: const TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D2236)),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            value: selectedReportType,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF9F6FB),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            items: const [
              DropdownMenuItem(value: "All", child: Text("All Reports")),
              DropdownMenuItem(value: "Comment", child: Text("Comment")),
              DropdownMenuItem(value: "Reply", child: Text("Reply")),
              DropdownMenuItem(value: "Chat", child: Text("Chat")),
              DropdownMenuItem(value: "Review", child: Text("Review")),
              DropdownMenuItem(value: "Bug", child: Text("Bug")),
              DropdownMenuItem(value: "Order Issue", child: Text("Order Issue")),
              DropdownMenuItem(value: "Payment Problem", child: Text("Payment Problem")),
              DropdownMenuItem(value: "Delivery", child: Text("Delivery")),
              DropdownMenuItem(value: "Others", child: Text("Others")),
            ],
            onChanged: (val) => setState(() => selectedReportType = val!),
          ),
        ),
      ],
    ),
    ElevatedButton.icon(
      onPressed: _exportReportsToCsv, // Now calls the functional export method
      icon: const Icon(Icons.download, size: 18, color: Colors.white),
      label: const Text("Export Reports", style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
  ],
),
                  const SizedBox(height: 20),

                  Expanded(
                    child: Card(
                      elevation: 2,
                      child: StreamBuilder<QuerySnapshot>(
                        stream: firestore.collection('reports').orderBy('timestamp', descending: false).snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snapshot.data?.docs ?? [];
                          var filtered = docs.where((doc) {
                            if (selectedReportType == "All") return true;
                            final type = (doc['type'] as String?) ?? '';
                            return type.toLowerCase() == selectedReportType.toLowerCase();
                          }).toList();

                          final totalItems = filtered.length;
                          final totalPages = totalItems == 0 ? 1 : (totalItems / _pageSize).ceil();
                          final start = _currentPage * _pageSize;
                          final end = (start + _pageSize).clamp(0, totalItems);
                          final pageDocs = totalItems > start ? filtered.sublist(start, end) : [];

                          return Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 300),
                                    child: DataTable(
                                      columnSpacing: 40,
                                      headingRowHeight: 56,
                                      dataRowHeight: 72,
                                      columns: const [
                                        DataColumn(label: Text("Report ID", style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text("Type")),
                                        DataColumn(label: Text("Reporter")),
                                        DataColumn(label: Text("Content")),
                                        DataColumn(label: Text("Reason")),
                                        DataColumn(label: Text("Date")),
                                        DataColumn(label: Text("Status")),
                                      ],
                                      rows: pageDocs.map((doc) {
                                        final data = doc.data() as Map<String, dynamic>;
                                        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                                        final dateStr = timestamp != null ? DateFormat('MMMM d, yyyy').format(timestamp) : '—';
                                        final status = (data['status'] ?? 'pending').toString().toLowerCase();

                                        return DataRow(
                                          onSelectChanged: (_) => _showReportDetails(doc),
                                          color: MaterialStateProperty.all(
                                            status == 'resolved' ? Colors.green.withOpacity(0.08) :
                                            status == 'dismissed' ? Colors.grey.withOpacity(0.08) : null,
                                          ),
                                          cells: [
                                            DataCell(Text(doc.id, style: const TextStyle(fontWeight: FontWeight.bold))),
                                            DataCell(_typeChip(data['type'] ?? 'Others')),
                                            DataCell(Text(data['reporterName'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600))),
                                            DataCell(SizedBox(width: 280, child: Text(data['content'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)))),
                                            DataCell(Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(color: _reasonColor(data['reason'] ?? ''), borderRadius: BorderRadius.circular(20)),
                                              child: Text(data['reason'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                            )),
                                            DataCell(Text(dateStr, style: const TextStyle(fontSize: 13))),
                                            DataCell(Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: status == 'pending' ? Colors.orange.withOpacity(0.2) :
                                                       status == 'resolved' ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(status[0].toUpperCase() + status.substring(1), style: TextStyle(
                                                color: status == 'pending' ? Colors.orange.shade700 : status == 'resolved' ? Colors.green.shade700 : Colors.grey.shade700,
                                                fontWeight: FontWeight.bold, fontSize: 12,
                                              )),
                                            )),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                              if (totalItems > _pageSize)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Color(0xFFF9F6FB), border: Border(top: BorderSide(color: Colors.grey.shade300))),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null, icon: const Icon(Icons.chevron_left)),
                                      Text("Page ${_currentPage + 1} of $totalPages", style: const TextStyle(fontWeight: FontWeight.w600)),
                                      IconButton(onPressed: end < totalItems ? () => setState(() => _currentPage++) : null, icon: const Icon(Icons.chevron_right)),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
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

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool active;
  final VoidCallback onTap;
  const _SidebarItem(this.icon, this.title, this.active, this.onTap, {Key? key}) : super(key: key);
  @override State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;
  @override Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: widget.active ? Colors.white.withOpacity(0.1) : (_hovering ? Colors.white.withOpacity(0.15) : Colors.transparent),
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