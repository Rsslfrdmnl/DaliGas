import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daligas/web/main_web.dart'; // ← This gives us 'firestore'
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
  final int itemsPerPage = 8;
  final TextEditingController searchController = TextEditingController();

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AdminWelcomeScreen()));
    }
  }

  Future<void> _deleteReview(String productId, String reviewId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Review"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Review deleted"), backgroundColor: Colors.red),
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
          _SidebarItem(Icons.assignment, "Reports", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminReportsScreen(), transitionDuration: Duration.zero))),
          _SidebarItem(Icons.settings, "Settings", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const AdminSettingsScreen(), transitionDuration: Duration.zero))),
          const Spacer(),
          _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
          const SizedBox(height: 20),
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

                  // Live Stats
                  StreamBuilder<QuerySnapshot>(
                    stream: firestore.collectionGroup('reviews').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Row(children: List.generate(4, (_) => _statCard(Icons.star, "...", "")));
                      }

                      final reviews = snapshot.data!.docs;

                      // Safely calculate stats
                      final total = reviews.length;

                      final sum = reviews.fold<double>(0.0, (prev, doc) {
                        final rating = doc['rating'];
                        if (rating is num) {
                          return prev + rating.toDouble();
                        }
                        return prev; // skip null or invalid
                      });

                      final avg = total > 0 ? (sum / total).toStringAsFixed(1) : "0.0";

                      final lowRatings = reviews.where((doc) {
                        final rating = doc['rating'];
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

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Customer Reviews", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ElevatedButton(
                        onPressed: () {}, // Export logic later
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D2236),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text("Export", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Search
                  TextField(
                    controller: searchController,
                    onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
                    decoration: InputDecoration(
                      hintText: "Search by customer, product, or comment...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Real-time Reviews Table
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: firestore.collectionGroup('reviews').orderBy('createdAt', descending: true).snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                        var docs = snapshot.data!.docs;

                        // Search filter
                        if (searchQuery.isNotEmpty) {
                          docs = docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final comment = (data['comment'] ?? '').toString().toLowerCase();
                            final rating = data['rating']?.toString() ?? '';
                            return comment.contains(searchQuery) || rating.contains(searchQuery);
                          }).toList();
                        }

                        final totalPages = (docs.length / itemsPerPage).ceil();
                        final start = currentPage * itemsPerPage;
                        final pageDocs = docs.length > start ? docs.sublist(start, (start + itemsPerPage).clamp(0, docs.length)) : <QueryDocumentSnapshot>[];

                        return Column(
                          children: [
                            Expanded(
                              child: Card(
                                elevation: 2,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columnSpacing: 40,
                                    columns: const [
                                      DataColumn(label: Text("Review ID")),
                                      DataColumn(label: Text("Product")),
                                      DataColumn(label: Text("Customer")),
                                      DataColumn(label: Text("Rating")),
                                      DataColumn(label: Text("Comment")),
                                      DataColumn(label: Text("Date Submitted")),
                                      DataColumn(label: Text("Action")),
                                    ],
                                    rows: pageDocs.map((doc) {
                                      final data = doc.data() as Map<String, dynamic>;
                                      final productId = doc.reference.parent.parent!.id;
                                      final reviewId = doc.id;
                                      final rating = (data['rating'] as num?)?.toInt() ?? 0;
                                      final timestamp = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

                                      return DataRow(cells: [
                                        DataCell(Text(reviewId.substring(0, 8).toUpperCase())),
                                        DataCell(FutureBuilder<DocumentSnapshot>(
                                          future: firestore.collection('products').doc(productId).get(),
                                          builder: (context, snap) => Text(snap.data?.exists == true ? snap.data!['title'] ?? 'Unknown' : 'Loading...'),
                                        )),
                                        DataCell(FutureBuilder<DocumentSnapshot>(
                                          future: firestore.collection('users').doc(data['userId']).get(),
                                          builder: (context, snap) => Text(snap.data?.exists == true ? snap.data!['fullName'] ?? 'Anonymous' : 'Loading...'),
                                        )),
                                        DataCell(Row(
                                          children: List.generate(5, (i) => Icon(
                                            i < rating ? Icons.star : Icons.star_border,
                                            color: Colors.amber,
                                            size: 18,
                                          )),
                                        )),
                                        DataCell(SizedBox(
                                          width: 220,
                                          child: Text(
                                            data['comment'] ?? 'No comment',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )),
                                        DataCell(Text(DateFormat('MM-dd-yyyy').format(timestamp))),
                                        DataCell(IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          tooltip: "Delete Review",
                                          onPressed: () => _deleteReview(productId, reviewId),
                                        )),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),

                            // Pagination
                            if (totalPages > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(onPressed: currentPage > 0 ? () => setState(() => currentPage--) : null, icon: const Icon(Icons.chevron_left)),
                                    Text("Page ${currentPage + 1} of $totalPages"),
                                    IconButton(onPressed: currentPage < totalPages - 1 ? () => setState(() => currentPage++) : null, icon: const Icon(Icons.chevron_right)),
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
        ],
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