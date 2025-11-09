import 'dart:io';
import 'package:flutter/foundation.dart'; // ← ADD THIS
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/messages_screen.dart';
import 'package:daligas/screens/purchases_screen.dart';
import 'package:daligas/screens/help_screen.dart';
import 'package:daligas/screens/welcome_screen.dart';
import 'package:daligas/screens/notifications_screen.dart';
import 'change_password_screen.dart';
import 'manage_address_screen.dart';

class AccountScreen extends StatefulWidget {
  final int currentIndex;
  const AccountScreen({super.key, this.currentIndex = 4});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String fullName = '';
  String email = '';
  String phone = '';
  String profileImage = '';
  bool isLoading = true;

  // ── Double-Back-to-Exit Logic ─────────────────────
  DateTime? _lastBackPress;
  static const int _backPressTimeout = 2;

  Future<bool> _onWillPop() async {
    final now = DateTime.now();

    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: _backPressTimeout)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.black87,
        ),
      );
      return false;
    }

    // Let system handle exit (Android back stack)
    return true;
  }
  // ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    setState(() => isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            fullName = (data['fullName'] ?? '') as String;
            email = (data['email'] ?? user.email ?? '') as String;
            phone = (data['phone'] ?? user.phoneNumber ?? '') as String;
            profileImage = (data['profileImage'] ?? '') as String;
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            fullName = 'User';
            email = user.email ?? '';
            phone = user.phoneNumber ?? '';
            profileImage = '';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print('fetchUserData error: $e'); // ← FIXED
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _menuTile(String title, {VoidCallback? onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF052238),
        appBar: AppBar(
          backgroundColor: const Color(0xFF052238),
          elevation: 0,
          titleSpacing: -8,
          automaticallyImplyLeading: false,
          leading: const SizedBox.shrink(),
          title: const Text(
            'Account',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: Colors.white),
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.grey,
                          backgroundImage: profileImage.isNotEmpty ? NetworkImage(profileImage) : null,
                          child: profileImage.isEmpty
                              ? const Icon(Icons.person, color: Colors.white, size: 40)
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            fullName.isNotEmpty ? fullName : 'User',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _menuTile('My Profile', onTap: () async {
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyProfileScreen(
                            fullName: fullName,
                            email: email,
                            phone: phone,
                            profileImage: profileImage,
                          ),
                        ),
                      );
                      if (updated == true) fetchUserData(); // ← Only refresh if needed
                    }),
                    _menuTile('Notifications', onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                    }),
                    _menuTile('Order History', onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasesScreen(currentIndex: 2)));
                    }),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          await _auth.signOut();
                          if (!mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                            (route) => false,
                          );
                        },
                        child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            currentIndex: widget.currentIndex,
            selectedItemColor: const Color(0xFF0D2236),
            unselectedItemColor: Colors.black,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            onTap: (index) {
              if (index == widget.currentIndex) return;
              switch (index) {
                case 0:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const HomeScreen(), transitionDuration: Duration.zero));
                  break;
                case 1:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const MessagesScreen(), transitionDuration: Duration.zero));
                  break;
                case 2:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const PurchasesScreen(currentIndex: 2), transitionDuration: Duration.zero));
                  break;
                case 3:
                  Navigator.pushReplacement(context, PageRouteBuilder(pageBuilder: (_, __, ___) => const HelpScreen(currentIndex: 3), transitionDuration: Duration.zero));
                  break;
                case 4:
                  break;
              }
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), activeIcon: Icon(Icons.shopping_bag, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.help_outline), activeIcon: Icon(Icons.help, color: Color(0xFF0D2236)), label: ''),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person, color: Color(0xFF0D2236)), label: ''),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MyProfileScreen
// ─────────────────────────────────────────────────────────────────────────────

class MyProfileScreen extends StatefulWidget {
  final String fullName;
  final String email;
  final String phone;
  final String profileImage;

  const MyProfileScreen({
    super.key,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.profileImage,
  });

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  late TextEditingController fullNameController;
  String? profileImageUrl;
  bool isUploading = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    profileImageUrl = widget.profileImage;
    fullNameController = TextEditingController(text: widget.fullName);
  }

  @override
  void dispose() {
    fullNameController.dispose();
    super.dispose();
  }

  String _normalizeForComparison(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (s.startsWith('0')) {
      s = '+63' + s.substring(1);
    }
    return s;
  }

  bool get _isPhoneLinked {
    final authPhone = _auth.currentUser?.phoneNumber ?? '';
    if (authPhone.isEmpty || widget.phone.isEmpty) return false;
    return _normalizeForComparison(authPhone) == _normalizeForComparison(widget.phone);
  }

  Future<void> pickAndCropImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: const Color(0xFF052238),
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Crop Image'),
      ],
    );
    if (cropped == null || !mounted) return;

    await uploadCroppedImage(File(cropped.path));
  }

  Future<void> uploadCroppedImage(File file) async {
    final user = _auth.currentUser;
    if (user == null || !mounted) return;

    setState(() => isUploading = true);
    try {
      final ref = _storage.ref().child('profile_pictures/${user.uid}.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await _firestore.collection('users').doc(user.uid).update({'profileImage': url});

      if (!mounted) return;
      setState(() {
        profileImageUrl = url;
        isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null || !mounted) return;

    final name = fullNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => isSaving = true);
    try {
      await _firestore.collection('users').doc(user.uid).update({'fullName': name});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!')),
      );
      Navigator.pop(context, true); // Signal refresh
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _openChangePassword() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
  }

  void _openManageAddress() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageAddressScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final phoneLinked = _isPhoneLinked;
    final currentUser = _auth.currentUser;
    final phoneToShow = widget.phone.isNotEmpty ? widget.phone : (currentUser?.phoneNumber ?? '');
    final emailToShow = widget.email.isNotEmpty ? widget.email : (currentUser?.email ?? '');

    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        backgroundColor: const Color(0xFF052238),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: isUploading ? null : pickAndCropImage,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey,
                    backgroundImage: profileImageUrl != null && profileImageUrl!.isNotEmpty
                        ? NetworkImage(profileImageUrl!)
                        : null,
                    child: (profileImageUrl == null || profileImageUrl!.isEmpty)
                        ? const Icon(Icons.person, size: 50, color: Colors.white)
                        : null,
                  ),
                  if (isUploading)
                    const Positioned.fill(
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Full Name
            Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  controller: fullNameController,
                  decoration: const InputDecoration(labelText: 'Full Name', border: InputBorder.none),
                ),
              ),
            ),

            // Email
            Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: ListTile(
                title: const Text('Email', style: TextStyle(fontSize: 12, color: Colors.black54)),
                subtitle: Text(emailToShow, style: const TextStyle(color: Colors.black87)),
                trailing: const Icon(Icons.lock, color: Colors.grey),
              ),
            ),

            // Phone
            Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: ListTile(
                title: const Text('Phone', style: TextStyle(fontSize: 12, color: Colors.black54)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(phoneToShow, style: const TextStyle(color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(
                      phoneLinked ? 'Verified' : 'Not verified',
                      style: TextStyle(
                        color: phoneLinked ? Colors.green : Colors.grey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                trailing: Icon(
                  phoneLinked ? Icons.check_circle : Icons.help_outline,
                  color: phoneLinked ? Colors.green : Colors.grey,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF052238),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: isSaving
                    ? const CircularProgressIndicator(color: Color(0xFF052238))
                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 16),

            // Links
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                title: const Text('Change Password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openChangePassword,
              ),
            ),
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                title: const Text('Manage Address'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openManageAddress,
              ),
            ),
          ],
        ),
      ),
    );
  }
}