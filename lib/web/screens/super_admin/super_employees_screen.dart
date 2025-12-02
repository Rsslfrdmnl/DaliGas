import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/web/main_web.dart';
import 'admin_welcome_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_sales_screen.dart';
import 'super_inventory_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';
import 'super_settings_screen.dart';

class SuperEmployeesScreen extends StatefulWidget {
  const SuperEmployeesScreen({super.key});
  @override
  State<SuperEmployeesScreen> createState() => _SuperEmployeesScreenState();
}

class _SuperEmployeesScreenState extends State<SuperEmployeesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String department = "Sales";
  int _currentPage = 0;

  Future<void> _logout(BuildContext context) async {
  await FirebaseAuth.instance.signOut();

  if (!context.mounted) {
    return;
  }

  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
}

  void _showAddEmployeeDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String selectedRole = 'employee';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Employee"),
        content: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: "Full Name")),
    const SizedBox(height: 12),
    TextField(controller: phoneCtrl, decoration: const InputDecoration(hintText: "Phone Number")),
    const SizedBox(height: 12),
    TextField(
      decoration: const InputDecoration(hintText: "Department (e.g. Sales, Logistics, Warehouse)"),
      onChanged: (val) => department = val.trim(),
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(
      value: selectedRole,
      items: const [
        DropdownMenuItem(value: "employee", child: Text("Employee")),
        DropdownMenuItem(value: "admin", child: Text("Admin")),
      ],
      onChanged: (val) => selectedRole = val!,
      decoration: const InputDecoration(labelText: "Role"),
    ),
  ],
),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
  onPressed: () {
    if (nameCtrl.text.trim().isNotEmpty && phoneCtrl.text.trim().isNotEmpty) {
      final data = {
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'role': selectedRole,
        'department': department.trim().isEmpty ? "N/A" : department.trim(),
        'status': 'Active',
      };

      // Save to correct collection based on role
      if (selectedRole == 'admin') {
        firestore.collection('admins').add(data);
      } else {
        firestore.collection('employees').add(data);
      }

      Navigator.pop(ctx);
      // Optional: Show success snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${selectedRole == 'admin' ? 'Admin' : 'Employee'} added successfully!")),
      );
    }
  },
  child: const Text("Add"),
),
        ],
      ),
    );
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ----- Sidebar (unchanged) -----
          Container(
            width: 220,
            color: const Color(0xFF0D2236),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.translate(offset: const Offset(-10, 0), child: Image.asset("assets/images/daligas_logo.png", height: 80)),
                    Transform.translate(offset: const Offset(-22, 0), child: const Text("DALI GAS", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white))),
                  ],
                ),
                const SizedBox(height: 30),
                _SidebarItem(Icons.dashboard, "Dashboard", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperAdminDashboard(), transitionDuration: Duration.zero))),
                _SidebarItem(Icons.bar_chart, "Sales", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperSalesScreen(), transitionDuration: Duration.zero))),
                _SidebarItem(Icons.inventory, "Inventory", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperInventoryScreen(), transitionDuration: Duration.zero))),
                _SidebarItem(Icons.people, "Employees", true, () {}),
                _SidebarItem(Icons.feedback, "Feedbacks", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperFeedbacksScreen(), transitionDuration: Duration.zero))),
                _SidebarItem(Icons.assignment, "Business Reports", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperReportsScreen(), transitionDuration: Duration.zero))),
                _SidebarItem(Icons.settings, "Settings", false, () => Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const SuperSettingsScreen(), transitionDuration: Duration.zero))),
                const Spacer(),
                _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ----- Main Content -----
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Employees", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E88E5), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                        onPressed: _showAddEmployeeDialog,
                        icon: const Icon(Icons.person_add, color: Colors.white),
                        label: const Text("Add Employee", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // FULL TABLE CARD with Search + Real-time Table + Pagination
                  Expanded(
                    child: Card(
                      elevation: 2,
                      child: Column(
                        children: [
                          // Search inside card
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val.toLowerCase();
                                  _currentPage = 0;
                                });
                              },
                              decoration: InputDecoration(
                                hintText: "Search by name or phone...",
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                            ),
                          ),

                          // Real-time Table
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: firestore.collection('employees').orderBy('name').snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                                var filtered = snapshot.data!.docs.where((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final name = (data['name'] as String?)?.toLowerCase() ?? '';
                                  final phone = (data['phone'] as String?)?.toLowerCase() ?? '';
                                  return name.contains(_searchQuery) || phone.contains(_searchQuery);
                                }).toList();

                                const itemsPerPage = 4;
                                final totalPages = (filtered.length / itemsPerPage).ceil();
                                final start = _currentPage * itemsPerPage;
                                final end = (start + itemsPerPage).clamp(0, filtered.length);
                                final pageItems = filtered.sublist(start, end);

                                return Column(
                                  children: [
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) => SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                            child: SizedBox(
                                              width: 1500,
                                              child: DataTable(
                                                columnSpacing: 30,
                                                columns: const [
                                                  DataColumn(label: Text("Name")),
                                                  DataColumn(label: Text("Role")),
                                                  DataColumn(label: Text("Department")),
                                                  DataColumn(label: Text("Contact")),
                                                  DataColumn(label: Text("Status")),
                                                ],
                                                rows: pageItems.map((doc) {
                                                  final data = doc.data() as Map<String, dynamic>;
                                                  final String name = data['name'] ?? '-';
                                                  final String role = (data['role'] ?? 'employee').toString().capitalize();
                                                  final String phone = data['phone'] ?? '-';
                                                  final String status = (data['status'] ?? 'Active') as String;
                                                  final bool isActive = status == 'Active';

                                                  return DataRow(cells: [
                                                    DataCell(Text(name)),
                                                    DataCell(Text(role)),
                                                    DataCell(Text(data['department'] ?? '-')),
                                                    DataCell(Text(phone)),
                                                    DataCell(
                                                      Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text(isActive ? "Active" : "Inactive", style: TextStyle(color: isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                                                          Switch(
                                                            value: isActive,
                                                            activeColor: Colors.green,
                                                            onChanged: (val) {
                                                              firestore.doc(doc.reference.path).update({'status': val ? 'Active' : 'Inactive'});
                                                            },
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

                                    // Pagination
                                    if (totalPages > 1)
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            IconButton(onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null, icon: const Icon(Icons.chevron_left)),
                                            const SizedBox(width: 20),
                                            Text("Page ${_currentPage + 1} of $totalPages", style: const TextStyle(fontWeight: FontWeight.w600)),
                                            const SizedBox(width: 20),
                                            IconButton(onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null, icon: const Icon(Icons.chevron_right)),
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
            ),
          ),
        ],
      ),
    );
  }
}

// Helper extension
extension StringExtension on String {
  String capitalize() => this[0].toUpperCase() + substring(1);
}

// Sidebar unchanged
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