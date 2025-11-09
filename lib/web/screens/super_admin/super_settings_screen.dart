import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_welcome_screen.dart';
import 'super_dashboard_screen.dart';
import 'super_sales_screen.dart';
import 'super_inventory_screen.dart';
import 'super_employees_screen.dart';
import 'super_feedbacks_screen.dart';
import 'super_reports_screen.dart';

class SuperSettingsScreen extends StatefulWidget {
  const SuperSettingsScreen({super.key});

  @override
  State<SuperSettingsScreen> createState() => _SuperSettingsScreenState();
}

class _SuperSettingsScreenState extends State<SuperSettingsScreen> {
  bool _darkModeEnabled = false;
  final _nameController = TextEditingController(text: "Admin User");
  final _emailController = TextEditingController(text: "admin@daligas.com");
  final _oldPassController = TextEditingController();
  final _newPassController = TextEditingController();

  // ✅ Logout
  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AdminWelcomeScreen()),
      );
    }
  }

  void _saveSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Settings saved successfully!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Sidebar ----
          Container(
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
                _SidebarItem(Icons.dashboard, "Dashboard", true, () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const SuperAdminDashboard(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                }),
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
                _SidebarItem(Icons.settings, "Settings", true, () {}),
                const Spacer(),
                _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
              ],
            ),
          ),

          // ---- Main Content ----
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Settings",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // ---- Account Info ----
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Account Information",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildTextField("Full Name", _nameController),
                          const SizedBox(height: 20),
                          _buildTextField("Email Address", _emailController),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // ---- Change Password ----
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Change Password",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildTextField("Old Password", _oldPassController,
                              obscureText: true),
                          const SizedBox(height: 20),
                          _buildTextField("New Password", _newPassController,
                              obscureText: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // ---- Preferences ----
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Preferences",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SwitchListTile(
                            title: const Text("Enable Dark Mode"),
                            activeColor: const Color(0xFF0D2236),
                            value: _darkModeEnabled,
                            onChanged: (val) {
                              setState(() => _darkModeEnabled = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // ---- Save Button ----
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D2236),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        "Save Changes",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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

  Widget _buildTextField(String label, TextEditingController controller,
      {bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
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
