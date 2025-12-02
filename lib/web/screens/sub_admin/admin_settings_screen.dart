import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/web/screens/super_admin/admin_welcome_screen.dart';
import 'package:daligas/web/main_web.dart';
import 'admin_dashboard_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_delivery_screen.dart';
import 'admin_feedbacks_screen.dart';
import 'admin_reports_screen.dart';

final FirebaseAuth auth = FirebaseAuth.instance;

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  late User? currentUser;
  DocumentSnapshot? adminDoc;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _oldPassController = TextEditingController();
  final _newPassController = TextEditingController();

  bool _darkModeEnabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    currentUser = auth.currentUser;
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    if (currentUser == null) return;

    try {
      final doc = await firestore.collection('admins').doc(currentUser!.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          adminDoc = doc;
          _nameController.text = data['name'] ?? 'Admin User';
          _emailController.text = data['email'] ?? currentUser!.email ?? '';
          _darkModeEnabled = data['darkMode'] ?? false;
        });
      }
    } catch (e) {
      print("Error loading admin data: $e");
    }
  }

  Future<void> _saveSettings() async {
  if (currentUser == null) return;

  setState(() => _isLoading = true);

  try {
    // Update Firestore with all changes, including dark mode
    await firestore.collection('admins').doc(currentUser!.uid).set({
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'darkMode': _darkModeEnabled,  // Only saved when user explicitly clicks Save
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Apply the dark mode setting to the ThemeManager only after saving
    await ThemeManager().setDarkMode(_darkModeEnabled);

    // Update email in Firebase Auth if changed
    if (_emailController.text.trim() != currentUser!.email) {
      await currentUser!.updateEmail(_emailController.text.trim());
    }

    // Change password if both fields filled
    if (_oldPassController.text.isNotEmpty && _newPassController.text.isNotEmpty) {
      if (_newPassController.text.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("New password must be at least 6 characters")),
        );
        setState(() => _isLoading = false);
        return;
      }

      final credential = EmailAuthProvider.credential(
        email: currentUser!.email!,
        password: _oldPassController.text,
      );

      await currentUser!.reauthenticateWithCredential(credential);
      await currentUser!.updatePassword(_newPassController.text);

      _oldPassController.clear();
      _newPassController.clear();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Settings saved successfully!"),
        backgroundColor: Colors.green,
      ),
    );
  } on FirebaseAuthException catch (e) {
    String message = "Failed to save settings";
    if (e.code == 'wrong-password') {
      message = "Old password is incorrect";
    } else if (e.code == 'email-already-in-use') {
      message = "Email is already in use";
    } else if (e.code == 'requires-recent-login') {
      message = "Please log out and log in again to change sensitive info";
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
    );
  } finally {
    setState(() => _isLoading = false);
  }
}

  Future<void> _logout(BuildContext context) async {
  await FirebaseAuth.instance.signOut();

  if (!context.mounted) {
    return;
  }

  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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

          _SidebarItem(Icons.dashboard, "Dashboard", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminDashboardScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.shopping_cart, "Orders", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminInventoryScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.inventory, "Inventory", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminInventoryScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.local_shipping, "Delivery Management", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminDeliveryScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.feedback, "Feedback", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminFeedbackScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.flag, "User Reports", false, () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const AdminReportsScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }),
          _SidebarItem(Icons.settings, "Settings", true, () {}),

          const Spacer(),
          _SidebarItem(Icons.logout, "Logout", false, () => _logout(context)),
          const SizedBox(height: 20),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Settings", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),

                  // Account Information
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Account Information", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 20),
                          _buildTextField("Full Name", _nameController, icon: Icons.person),
                          const SizedBox(height: 16),
                          _buildTextField("Email Address", _emailController, icon: Icons.email),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Change Password
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Change Password", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 20),
                          _buildTextField("Current Password", _oldPassController, obscureText: true, icon: Icons.lock),
                          const SizedBox(height: 16),
                          _buildTextField("New Password", _newPassController, obscureText: true, icon: Icons.lock_outline),
                          const SizedBox(height: 8),
                          Text(" Leave blank if you don't want to change password", style: TextStyle(color: Colors.black, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Preferences
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Preferences", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 20),
                          SwitchListTile(
  title: const Text("Enable Dark Mode"),
  subtitle: const Text("Switch to dark theme across the admin panel"),
  activeColor: const Color(0xFF0D2236),
  value: _darkModeEnabled,
  onChanged: (val) {
    // Only update the local state, do not save to ThemeManager or Firestore
    setState(() => _darkModeEnabled = val);
  },
),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Save Button
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 200,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveSettings,
                        icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, color: Colors.white,),
                        label: Text(_isLoading ? "Saving..." : "Save Changes", style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D2236),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      {bool obscureText = false, IconData? icon}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: !_isLoading,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF0D2236)) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF0D2236), width: 2),
        ),
      ),
    );
  }
}

// Your original SidebarItem – unchanged
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