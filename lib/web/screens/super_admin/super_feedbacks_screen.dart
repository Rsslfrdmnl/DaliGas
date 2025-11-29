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
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

class SuperFeedbacksScreen extends StatefulWidget {
  const SuperFeedbacksScreen({super.key});
  @override
  State<SuperFeedbacksScreen> createState() => _SuperFeedbacksScreenState();
}

class _SuperFeedbacksScreenState extends State<SuperFeedbacksScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 0;
  final int _itemsPerPage = 4;

  final Map<String, String> _productCache = {};
  final Map<String, String> _userCache = {};

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminWelcomeScreen()));
    }
  }

  // Export to CSV
  void _exportToCsv() async {
    try {
      final snapshot = await firestore.collectionGroup('reviews').get();
      final rows = <List<String>>[
        ['Feedback ID', 'Type', 'Customer Name', 'Rating', 'Date Submitted', 'Status', 'Comment', 'Reply']
      ];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final productId = doc.reference.parent.parent!.id;
        final userId = data['userId'] as String?;
        final reviewId = doc.id;
        final rating = (data['rating'] as num?)?.toInt() ?? 0;
        final comment = (data['review'] ?? data['comment'] ?? '').toString();
        final reply = data['adminReply']?.toString() ?? '';
        final timestamp = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        String productName = _productCache[productId] ?? 'Unknown';
        if (!_productCache.containsKey(productId)) {
          final p = await firestore.collection('products').doc(productId).get();
          productName = p.exists ? (p.data()?['name'] ?? 'Unknown') : 'Deleted';
          _productCache[productId] = productName;
        }

        String userName = 'Anonymous';
        if (userId != null) {
          userName = _userCache[userId] ?? 'Anonymous';
          if (!_userCache.containsKey(userId)) {
            final u = await firestore.collection('users').doc(userId).get();
            userName = u.exists ? (u.data()?['fullName'] ?? 'Anonymous') : 'Deleted';
            _userCache[userId] = userName;
          }
        }

        final status = data['hasReply'] == true ? 'Resolved' : 'Pending';

        rows.add([
          reviewId.substring(0, 8).toUpperCase(),
          productName,
          userName,
          rating.toString(),
          DateFormat('MMMM d, yyyy').format(timestamp),
          status,
          comment.replaceAll('\n', ' '),
          reply.replaceAll('\n', ' '),
        ]);
      }

      final csv = rows.map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(',')).join('\r\n');
      final blob = html.Blob([utf8.encode(csv)]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'feedbacks_export_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv')
        ..click();
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exported successfully!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e")));
    }
  }

  Future<void> _replyToReview(String productId, String reviewId, String comment) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reply to Feedback"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Customer Comment:", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(comment, maxLines: 5, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          TextField(controller: controller, maxLines: 4, decoration: const InputDecoration(hintText: "Your reply...", border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Send")),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      await firestore.collection('products').doc(productId).collection('reviews').doc(reviewId).update({
        'adminReply': controller.text.trim(),
        'hasReply': true,
        'repliedAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reply sent!"), backgroundColor: Colors.green));
    }
  }

  Future<void> _deleteReview(String productId, String reviewId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Feedback"),
        content: const Text("This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await firestore.collection('products').doc(productId).collection('reviews').doc(reviewId).delete();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Feedback deleted"), backgroundColor: Colors.red));
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
              _SidebarItem(Icons.bar_chart, "Sales", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperSalesScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.inventory, "Inventory", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperInventoryScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.people, "Employees", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperEmployeesScreen(), transitionDuration: Duration.zero))),
              _SidebarItem(Icons.feedback, "Feedbacks", true, () {}),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Feedbacks", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                // Live Stats
                StreamBuilder<QuerySnapshot>(
                  stream: firestore.collectionGroup('reviews').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(4, (_) => _statCard(Icons.star, "...", "")));
                    }
                    final reviews = snapshot.data!.docs;

                    final total = reviews.length;
                    final sum = reviews.fold(0.0, (s, d) => s + ((d['rating'] as num?)?.toDouble() ?? 0));
                    final avg = total > 0 ? (sum / total).toStringAsFixed(1) : "0.0";

                    final resolved = reviews.where((d) {
                      final data = d.data() as Map<String, dynamic>?;
                      return data?['hasReply'] == true;
                    }).length;
                    final pending = total - resolved;

                    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      _statCard(Icons.star, avg, "Average Rating"),
                      _statCard(Icons.feedback, total.toString(), "Total Feedback"),
                      _statCard(Icons.check_circle, resolved.toString(), "Resolved"),
                      _statCard(Icons.hourglass_top, pending.toString(), "Pending Feedback"),
                    ]);
                  },
                ),
                const SizedBox(height: 30),

                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Customer Feedbacks", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ElevatedButton(onPressed: _exportToCsv, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D2236), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)), child: const Text("Export", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 20),

                // Full Table Card
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                          decoration: InputDecoration(hintText: "Search feedbacks...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                        ),
                      ),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: firestore.collectionGroup('reviews').orderBy('createdAt', descending: true).snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                            var filtered = snapshot.data!.docs.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final comment = (data['review'] ?? data['comment'] ?? '').toString().toLowerCase();
                              return comment.contains(_searchQuery);
                            }).toList();

                            final totalPages = (filtered.length / _itemsPerPage).ceil();
                            final start = _currentPage * _itemsPerPage;
                            final pageItems = filtered.sublist(start, (start + _itemsPerPage).clamp(0, filtered.length));

                            return Column(children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) => SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                      child: SizedBox(
                                        width: 1500,
                                        child: DataTable(
                                          columnSpacing: 40,
                                          columns: const [
  DataColumn(label: Text("Review ID", style: TextStyle(fontWeight: FontWeight.w600))),
  DataColumn(label: Text("Product", style: TextStyle(fontWeight: FontWeight.w600))),
  DataColumn(label: Text("Customer", style: TextStyle(fontWeight: FontWeight.w600))),
  DataColumn(label: Text("Rating", style: TextStyle(fontWeight: FontWeight.w600))),
  DataColumn(label: Text("Comment", style: TextStyle(fontWeight: FontWeight.w600))),
  DataColumn(label: Text("Date Submitted", style: TextStyle(fontWeight: FontWeight.w600))),
  DataColumn(label: Text("Action", style: TextStyle(fontWeight: FontWeight.w600))),
],
                                          rows: pageItems.map((doc) {
                                            final data = doc.data() as Map<String, dynamic>;
                                            final productId = doc.reference.parent.parent!.id;
                                            final reviewId = doc.id;
                                            final rating = (data['rating'] as num?)?.toInt() ?? 0;
                                            final timestamp = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                                            final hasReply = (data['hasReply'] as bool?) == true;

                                            return DataRow(cells: [
  DataCell(Text(reviewId.substring(0, 8).toUpperCase())),
  
  // Product
  // PRODUCT NAME – fixed
DataCell(
  FutureBuilder<String>(
    future: (() async {
      if (_productCache.containsKey(productId)) {
        return _productCache[productId]!; // already String
      }
      final snap = await firestore.collection('products').doc(productId).get();
      final name = snap.exists
          ? (snap.data()?['name']?.toString() ?? 'Unknown Product')
          : 'Deleted Product';
      _productCache[productId] = name;
      return name; // ← this is a String
    })(), // ← the ()() calls it and returns Future<String>
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Text('Loading...');
      }
      return Text(snapshot.data ?? 'Unknown');
    },
  ),
),

// CUSTOMER NAME – fixed (exactly the same pattern)
DataCell(
  FutureBuilder<String>(
    future: (() async {
      final uid = data['userId'] as String?;
      if (uid == null) return 'Anonymous';
      if (_userCache.containsKey(uid)) {
        return _userCache[uid]!;
      }
      final snap = await firestore.collection('users').doc(uid).get();
      final name = snap.exists
          ? (snap.data()?['fullName']?.toString() ?? 'Anonymous')
          : 'Deleted User';
      _userCache[uid] = name;
      return name; // ← String
    })(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Text('Loading...');
      }
      return Text(snapshot.data ?? 'Anonymous');
    },
  ),
),

  // Rating
  DataCell(Row(
    children: List.generate(5, (i) => Icon(
      i < rating ? Icons.star : Icons.star_border,
      color: Colors.amber,
      size: 20,
    )),
  )),

  // Comment + Replied Badge (EXACTLY like Admin screen)
  // COMMENT COLUMN – EXACTLY like AdminFeedbackScreen
DataCell(
  GestureDetector(
    onTap: () {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              const Icon(Icons.rate_review, color: Colors.amber, size: 28),
              const SizedBox(width: 12),
              const Text("Full Review", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: FutureBuilder<Map<String, String>>(
            future: Future(() async {
              final productName = _productCache.containsKey(productId)
                  ? _productCache[productId]!
                  : await firestore.collection('products').doc(productId).get().then((s) => s.exists ? (s.data()?['name'] ?? 'Unknown') : 'Deleted Product');
              final userName = data['userId'] == null
                  ? "Anonymous"
                  : _userCache.containsKey(data['userId'])
                      ? _userCache[data['userId']]!
                      : await firestore.collection('users').doc(data['userId']).get().then((s) => s.exists ? (s.data()?['fullName'] ?? 'Anonymous') : 'Deleted User');
              return {'product': productName, 'user': userName};
            }),
            builder: (context, snap) {
              final names = snap.data ?? {'product': 'Loading...', 'user': 'Loading...'};
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Product: ${names['product']}", style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text("Customer: ${names['user']}", style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  const Text("Rating:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(5, (i) => Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 26,
                    )),
                  ),
                  const SizedBox(height: 16),
                  const Text("Comment:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(data['review'] ?? data['comment'] ?? 'No comment', style: const TextStyle(fontSize: 15)),
                  if (hasReply) ...[
                    const SizedBox(height: 16),
                    const Text("Your Reply:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border(left: BorderSide(color: Colors.green, width: 4)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(data['adminReply'].toString(), style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text("Date: ${DateFormat('MMMM d, yyyy • hh:mm a').format(timestamp)}", style: const TextStyle(color: Colors.grey)),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close", style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      );
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.click,  // ← Hand cursor
      child: Row(
        children: [
          Expanded(
            child: Text(
              () {
                final c = (data['review'] ?? data['comment'] ?? 'No comment').toString();
                return c.length > 40 ? "${c.substring(0, 40)}... (View Full)" : c;
              }(),
              style: TextStyle(
                color: Colors.blue[700],
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasReply)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "Replied",
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    ),
  ),
),

  // Date Submitted
  DataCell(Text(DateFormat('MMMM d, yyyy').format(timestamp))),

  // Action (Reply + Delete)
  DataCell(
  Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: const Icon(Icons.reply, color: Colors.blue, size: 22),
        tooltip: "Reply",
        onPressed: () => _replyToReview(productId, reviewId, data['review'] ?? data['comment'] ?? ''),
      ),
      const SizedBox(width: 8),
      IconButton(
        icon: const Icon(Icons.delete, color: Colors.red, size: 22),
        tooltip: "Delete",
        onPressed: () => _deleteReview(productId, reviewId),
      ),
    ],
  ),
),
]);
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (totalPages > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
                                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    IconButton(onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null, icon: const Icon(Icons.chevron_left)),
                                    const SizedBox(width: 20),
                                    Text("Page ${_currentPage + 1} of $totalPages", style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 20),
                                    IconButton(onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null, icon: const Icon(Icons.chevron_right)),
                                  ]),
                                ),
                            ]);
                          },
                        ),
                      ),
                    ]),
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
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Icon(icon, size: 36, color: const Color(0xFF0D2236)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 14)),
          ]),
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
          color: _hovering ? Colors.white.withOpacity(0.15) : (widget.active ? Colors.white.withOpacity(0.1) : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ListTile(leading: Icon(widget.icon, color: Colors.white), title: Text(widget.title, style: const TextStyle(color: Colors.white)), onTap: widget.onTap),
      ),
    );
  }
}