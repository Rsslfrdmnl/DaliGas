import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_address_screen.dart';
import 'package:daligas/main_mobile.dart';

class ManageAddressScreen extends StatefulWidget {
  const ManageAddressScreen({super.key});

  @override
  State<ManageAddressScreen> createState() => _ManageAddressScreenState();
}

class _ManageAddressScreenState extends State<ManageAddressScreen> {
  final user = FirebaseAuth.instance.currentUser;
  List<Map<String, dynamic>> addresses = [];

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final doc = await firestore
        .collection('users')
        .doc(user!.uid)
        .get();
    final data = doc.data();
    if (data != null && data['addresses'] != null) {
      List<Map<String, dynamic>> loaded =
          List<Map<String, dynamic>>.from(data['addresses']);

      // Sort: active first
      loaded.sort((a, b) {
        final aActive = (a['isActive'] ?? false) ? 0 : 1;
        final bActive = (b['isActive'] ?? false) ? 0 : 1;
        return aActive.compareTo(bActive);
      });

      setState(() => addresses = loaded);
    }
  }

  // Toggle active state (activate or deactivate)
  Future<void> _toggleActive(int index) async {
    final bool currentlyActive = addresses[index]['isActive'] ?? false;
    final bool willBeActive = !currentlyActive;

    // Update all addresses
    for (int i = 0; i < addresses.length; i++) {
      addresses[i]['isActive'] = willBeActive && (i == index);
    }

    await firestore
        .collection('users')
        .doc(user!.uid)
        .update({'addresses': addresses});

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          willBeActive
              ? 'Address activated'
              : 'Address deactivated (no active address)',
        ),
      ),
    );

    // Notify parent screen (e.g., Home) to refresh
    Navigator.pop(context, true);
  }

  // Edit existing address (replace at same index)
  Future<void> _editAddress(int index, Map<String, dynamic> address) async {
    final updatedAddress = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddAddressScreen(editMode: true, address: address),
      ),
    );

    // Expect the full updated map back
    if (updatedAddress != null && updatedAddress is Map<String, dynamic>) {
      setState(() {
        addresses[index] = updatedAddress;
      });

      await firestore
          .collection('users')
          .doc(user!.uid)
          .update({'addresses': addresses});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address updated successfully')),
      );

      // Re-sort in case active status changed during edit
      _loadAddresses();
    }
  }

  Future<void> _deleteAddress(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this address?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        addresses.removeAt(index);
      });

      await firestore
          .collection('users')
          .doc(user!.uid)
          .update({'addresses': addresses});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address deleted')),
      );
    }
  }

  Future<void> _addAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddAddressScreen()),
    );

    if (result != null) {
      _loadAddresses();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Manage Address',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: addresses.isEmpty
            ? const Center(
                child: Text(
                  'No saved addresses yet.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : ListView.builder(
                itemCount: addresses.length,
                itemBuilder: (context, index) {
                  final a = addresses[index];
                  final isActive = a['isActive'] == true;

                  return GestureDetector(
                    onTap: () => _toggleActive(index),
                    child: Card(
                      color: isActive ? const Color(0xFFE8F5E9) : Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isActive ? Colors.green : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      elevation: isActive ? 6 : 2,
                      child: ListTile(
                        title: Text(
                          '${a['street'] ?? ''}, ${a['barangay'] ?? ''}, ${a['city'] ?? ''}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${a['province'] ?? ''}, ${a['postal'] ?? ''}',
                          style: const TextStyle(color: Colors.black87),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isActive)
                              const Icon(Icons.check_circle, color: Colors.green),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editAddress(index, a),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _deleteAddress(index),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF052238),
        onPressed: _addAddress,
        child: const Icon(Icons.add),
      ),
    );
  }
}