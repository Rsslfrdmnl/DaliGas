import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/main_web.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';

import 'admin_dashboard_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_screen.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  String searchQuery = '';
  int currentPage = 0;
  final int itemsPerPage = 4;
  final TextEditingController searchController = TextEditingController();

  final Map<String, String> _productCache = {};
  final Map<String, String> _userCache = {};

  void _exportReviewsToCsv() async {
  try {
    // Fetch all reviews using collectionGroup
    final reviewsSnapshot = await firestore.collectionGroup('reviews').get();

    final rows = <List<String>>[];

    // Add header row
    rows.add([
      'Review ID',
      'Product Name',
      'Customer Name',
      'Rating',
      'Comment',
      'Admin Reply',
      'Date Submitted',
      'Has Reply'
    ]);

    for (var doc in reviewsSnapshot.docs) {
      final data = doc.data();
      final productId = doc.reference.parent.parent!.id;
      final userId = data['userId'] as String?;
      final reviewId = doc.id;
      final rating = (data['rating'] as num?)?.toInt() ?? 0;
      final comment = data['review'] ?? data['comment'] ?? '';
      final adminReply = data['adminReply']?.toString() ?? '';
      final timestamp = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

      // Get product name
      String productName = 'Unknown Product';
      try {
        final productDoc = await firestore.collection('products').doc(productId).get();
        if (productDoc.exists) {
          productName = productDoc.data()?['name']?.toString() ?? 'Unknown Product';
        }
      } catch (e) {
        productName = 'Error retrieving product';
      }

      // Get customer name
      String customerName = 'Anonymous';
      if (userId != null && userId.isNotEmpty) {
        try {
          final userDoc = await firestore.collection('users').doc(userId).get();
          if (userDoc.exists) {
            customerName = userDoc.data()?['fullName']?.toString() ?? 'Anonymous';
          }
        } catch (e) {
          customerName = 'Error retrieving user';
        }
      }

      rows.add([
        reviewId,
        productName,
        customerName,
        rating.toString(),
        comment,
        adminReply,
        DateFormat('MMMM d, yyyy - hh:mm a').format(timestamp),
        data['hasReply'] == true ? 'Yes' : 'No',
      ]);
    }

    // Convert to CSV string
    final csvString = _simpleCsvConvert(rows);

    // Create and download the file
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final blob = html.Blob([utf8.encode(csvString)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'reviews_export_$timestamp.csv')
      ..click();

    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reviews exported successfully (${rows.length - 1} reviews)'),
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error exporting reviews: $e')),
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

  if (!context.mounted) {
    return;
  }

  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
}

  Future<void> _deleteReview(String productId, String reviewId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Review"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await firestore
          .collection('products')
          .doc(productId)
          .collection('reviews')
          .doc(reviewId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Review deleted"), backgroundColor: Colors.red),
        );
      }
    }
  }

Future<void> _replyToReview(String productId, String reviewId, String userId, String currentComment) async {
  final TextEditingController replyController = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Reply to Review"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Original comment:", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(currentComment, maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          TextField(
            controller: replyController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: "Write your reply...",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Send Reply"),
        ),
      ],
    ),
  );

  if (result == true && replyController.text.trim().isNotEmpty) {
    await firestore
        .collection('products')
        .doc(productId)
        .collection('reviews')
        .doc(reviewId)
        .update({
      'adminReply': replyController.text.trim(),
      'repliedAt': FieldValue.serverTimestamp(),
      'hasReply': true,
    });

    // Optional: send notification to user here later
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reply sent successfully"), backgroundColor: Colors.green),
      );
    }
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
                child: const Text("DALI GAS", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 30),

          _SidebarItem(Icons.dashboard, "Dashboard", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminDashboardScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.shopping_cart, "Orders", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminOrdersScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.inventory, "Inventory", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminInventoryScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.local_shipping, "Delivery Management", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminDeliveryScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.feedback, "Feedback", true, () {}),
          _SidebarItem(Icons.flag, "User Reports", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminReportsScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.settings, "Settings", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminSettingsScreen(), transitionDuration: Duration.zero))),
          const Spacer(),
          _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // YOUR ORIGINAL ICON-BASED STAT CARDS — UNTOUCHED & PERFECT
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
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5FA),
      body: Row(
        children: [
          _buildSidebar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Feedbacks", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 20),

                  // YOUR ORIGINAL ICON STATS — NOW WITH REAL LOW RATINGS
                  StreamBuilder<QuerySnapshot>(
                    stream: firestore.collectionGroup('reviews').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Row(children: List.generate(4, (_) => _statCard(Icons.star, "...", "")));
                      }

                      final reviews = snapshot.data!.docs;
                      final total = reviews.length;
                      final sum = reviews.fold<double>(0.0, (prev, doc) {
                        final rating = (doc.data() as Map<String, dynamic>)['rating'];
                        return rating is num ? prev + rating.toDouble() : prev;
                      });
                      final avg = total > 0 ? (sum / total).toStringAsFixed(1) : "0.0";

                      final lowRatings = reviews.where((doc) {
                        final rating = (doc.data() as Map<String, dynamic>)['rating'];
                        return rating is num && rating <= 3;
                      }).length;

                      return Row(
                        children: [
                          _statCard(Icons.star, avg, "Average Rating"),
                          const SizedBox(width: 16),
                          _statCard(Icons.feedback, total.toString(), "Total Feedback"),
                          const SizedBox(width: 16),
                          _statCard(Icons.check_circle, total.toString(), "Published"),
                          const SizedBox(width: 16),
                          _statCard(Icons.sentiment_dissatisfied, lowRatings.toString(), "Low Ratings"),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 30),

                  // EXACT SAME CARD + PAGINATOR AS ORDERS SCREEN — NO MORE CHANGES
                  Expanded(
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: TextField(
                                controller: searchController,
                                onChanged: (val) {
                                  setState(() {
                                    searchQuery = val.toLowerCase();
                                    currentPage = 0;
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: "Search by customer, product, or comment...",
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
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
                                    final productId = doc.reference.parent.parent!.id;
                                    final userId = data['userId'] as String?;
                                    final productName = _productCache[productId]?.toLowerCase() ?? '';
                                    final userName = _userCache[userId]?.toLowerCase() ?? '';
                                    return comment.contains(searchQuery) || productName.contains(searchQuery) || userName.contains(searchQuery);
                                  }).toList();

                                  final totalPages = (filtered.length / itemsPerPage).ceil();
                                  final start = currentPage * itemsPerPage;
                                  final pageItems = filtered.length > start
                                      ? filtered.sublist(start, (start + itemsPerPage).clamp(0, filtered.length))
                                      : <QueryDocumentSnapshot>[];

                                  return Column(
                                    children: [
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: Container(
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.grey.shade300),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: DataTable(
                                              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                              dataRowHeight: 70,
                                              headingRowHeight: 50,
                                              horizontalMargin: 16,
                                              columnSpacing: 32,
                                              border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1)),
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
                                                final userId = data['userId'] as String?;
                                                final reviewId = doc.id;
                                                final rating = (data['rating'] as num?)?.toInt() ?? 0;
                                                final timestamp = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

                                                return DataRow(cells: [
                                                  DataCell(Text(reviewId.substring(0, 8).toUpperCase())),
                                                  DataCell(FutureBuilder<String>(
                                                    future: _productCache.containsKey(productId)
                                                        ? Future.value(_productCache[productId]!)
                                                        : firestore.collection('products').doc(productId).get().then((s) {
                                                            final n = s.exists ? (s.data()?['name'] ?? 'Unknown') : 'Deleted';
                                                            _productCache[productId] = n;
                                                            return n;
                                                          }),
                                                    builder: (_, snap) => Text(snap.data ?? "Loading..."),
                                                  )),
                                                  DataCell(FutureBuilder<String>(
                                                    future: userId == null
                                                        ? Future.value("Anonymous")
                                                        : _userCache.containsKey(userId)
                                                            ? Future.value(_userCache[userId]!)
                                                            : firestore.collection('users').doc(userId).get().then((s) {
                                                                final n = s.exists ? (s.data()?['fullName'] ?? 'Anonymous') : 'Deleted';
                                                                _userCache[userId] = n;
                                                                return n;
                                                              }),
                                                    builder: (_, snap) => Text(snap.data ?? "Loading..."),
                                                  )),
                                                  DataCell(Row(
                                                    children: List.generate(5, (i) => Icon(
                                                          i < rating ? Icons.star : Icons.star_border,
                                                          color: Colors.amber,
                                                          size: 20,
                                                        )),
                                                  )),
                                                  DataCell(
                                                    GestureDetector(
                                                      onTap: () {
                                                        // ← Your existing full review dialog code stays exactly the same
                                                        showDialog(
                                                          context: context,
                                                          builder: (context) => AlertDialog(
                                                            title: Row(
                                                              children: [
                                                                const Icon(Icons.rate_review, color: Colors.amber),
                                                                const SizedBox(width: 10),
                                                                const Text("Full Review", style: TextStyle(fontWeight: FontWeight.bold)),
                                                              ],
                                                            ),
                                                            content: FutureBuilder<Map<String, String>>(
                                                              future: Future(() async {
                                                                final productName = _productCache.containsKey(productId)
                                                                    ? _productCache[productId]!
                                                                    : await firestore.collection('products').doc(productId).get().then((s) => s.exists ? (s.data()?['name'] ?? 'Unknown') : 'Deleted');
                                                                final userName = userId == null
                                                                    ? "Anonymous"
                                                                    : _userCache.containsKey(userId)
                                                                        ? _userCache[userId]!
                                                                        : await firestore.collection('users').doc(userId!).get().then((s) => s.exists ? (s.data()?['fullName'] ?? 'Anonymous') : 'Deleted');
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
                                                                    const SizedBox(height: 12),
                                                                    const Text("Rating:", style: TextStyle(fontWeight: FontWeight.bold)),
                                                                    Row(
                                                                      children: List.generate(5, (i) => Icon(
                                                                            i < rating ? Icons.star : Icons.star_border,
                                                                            color: Colors.amber,
                                                                            size: 24,
                                                                          )),
                                                                    ),
                                                                    const SizedBox(height: 12),
                                                                    const Text("Comment:", style: TextStyle(fontWeight: FontWeight.bold)),
                                                                    const SizedBox(height: 8),
                                                                    Text(
                                                                      data['review'] ?? data['comment'] ?? 'No comment',
                                                                      style: const TextStyle(fontSize: 15),
                                                                    ),
                                                  
                                                                    // Show admin reply if exists
                                                                    if (data['adminReply'] != null && data['adminReply'].toString().isNotEmpty) ...[
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
                                                                        child: Text(
                                                                          data['adminReply'].toString(),
                                                                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                                                                        ),
                                                                      ),
                                                                    ],
                                                  
                                                                    const SizedBox(height: 12),
                                                                    Text("Date: ${DateFormat('MMMM d, yyyy • hh:mm a').format(timestamp)}", style: TextStyle(color: Colors.black)),
                                                                  ],
                                                                );
                                                              },
                                                            ),
                                                            actions: [
                                                              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              () {
                                                                final comment = (data['review'] ?? data['comment'] ?? 'No comment').toString();
                                                                return comment.length > 40
                                                                    ? "${comment.substring(0, 40)}... (View Full)"
                                                                    : comment;
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
                                                          // Replied Badge
                                                          if (data['hasReply'] == true)
                                                            Container(
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
                                                  DataCell(Text(DateFormat('MMMM d, yyyy').format(timestamp))),
                                                  DataCell(
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        // Reply Button
                                                        IconButton(
                                                          tooltip: "Reply",
                                                          icon: const Icon(Icons.reply, color: Colors.blue),
                                                          onPressed: () {
                                                            final comment = data['review'] ?? data['comment'] ?? '';
                                                            _replyToReview(productId, reviewId, userId ?? '', comment);
                                                          },
                                                        ),
                                                        // Delete Button
                                                        IconButton(
                                                          tooltip: "Delete",
                                                          icon: const Icon(Icons.delete, color: Colors.red),
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

                                      // EXACT SAME PAGINATION AS YOUR ORDERS SCREEN — NO MORE TOUCHING
                                      if (totalPages > 1)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 16),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                onPressed: currentPage > 0 ? () => setState(() => currentPage--) : null,
                                                icon: const Icon(Icons.chevron_left),
                                              ),
                                              Text("Page ${currentPage + 1} of $totalPages"),
                                              IconButton(
                                                onPressed: currentPage < totalPages - 1 ? () => setState(() => currentPage++) : null,
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

                            const SizedBox(height: 16),
                            Align(
  alignment: Alignment.centerRight,
  child: ElevatedButton.icon(
    onPressed: _exportReviewsToCsv, // Now calls the functional export method
    icon: const Icon(
      Icons.download,
      size: 18,
      color: Colors.white,
    ),
    label: const Text("Export Reviews", style: TextStyle(color: Colors.white)),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.blue,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
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