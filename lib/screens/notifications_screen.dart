import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daligas/main_mobile.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool orderUpdates = true;
  bool deliveryReminders = true;
  bool chatMessages = true;
  bool promotions = false;
  bool isLoading = true;
  bool isSaving = false;

  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (user == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      final doc = await firestore
          .collection('users')
          .doc(user!.uid)
          .get();

      if (doc.exists && doc.data()!.containsKey('notifications')) {
        final data = doc['notifications'];
        setState(() {
          orderUpdates = data['orderUpdates'] ?? true;
          deliveryReminders = data['deliveryReminders'] ?? true;
          chatMessages = data['chatMessages'] ?? true;
          promotions = data['promotions'] ?? false;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading notification settings: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateSettings() async {
    if (user == null) return;

    setState(() => isSaving = true);

    try {
      await firestore.collection('users').doc(user!.uid).set({
        'notifications': {
          'orderUpdates': orderUpdates,
          'deliveryReminders': deliveryReminders,
          'chatMessages': chatMessages,
          'promotions': promotions,
        }
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification preferences updated!')),
        );

        // Delay slightly to show the snackbar before returning
        await Future.delayed(const Duration(milliseconds: 600));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error updating notification settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update settings. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        backgroundColor: const Color(0xFF052238),
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Notification Preferences',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                _buildSwitchTile(
                  'Order Updates',
                  'Get notified about changes to your orders.',
                  orderUpdates,
                  (val) => setState(() => orderUpdates = val),
                ),
                _buildSwitchTile(
                  'Delivery Reminders',
                  'Receive reminders for upcoming deliveries.',
                  deliveryReminders,
                  (val) => setState(() => deliveryReminders = val),
                ),
                _buildSwitchTile(
                  'Chat Messages',
                  'Get alerts for new messages from drivers or admins.',
                  chatMessages,
                  (val) => setState(() => chatMessages = val),
                ),
                _buildSwitchTile(
                  'Promotions & Offers',
                  'Stay updated about new discounts or deals.',
                  promotions,
                  (val) => setState(() => promotions = val),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: isSaving ? null : _updateSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: null,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Card(
      color: const Color(0xFF06385A),
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        value: value,
        activeColor: Colors.green,
        onChanged: onChanged,
      ),
    );
  }
}
