import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:rxdart/rxdart.dart';
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/messages_screen.dart';
import 'package:daligas/screens/purchases_screen.dart';
import 'package:daligas/screens/help_screen.dart';
import 'package:daligas/screens/welcome_screen.dart';
import 'package:daligas/screens/notifications_screen.dart';
import 'package:daligas/main_mobile.dart';
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
  final _firestore = firestore;

  // ── Reactive Streams ─────────────────────
  final BehaviorSubject<Map<String, dynamic>> _userData = BehaviorSubject.seeded({
    'fullName': '',
    'email': '',
    'phone': '',
    'profileImage': '',
  });
  final BehaviorSubject<bool> _isLoading = BehaviorSubject.seeded(true);

  StreamSubscription? _userSub;

  // ── Double-Back-to-Exit ──────────────────
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
    return true;
  }

  @override
  void initState() {
    super.initState();
    _listenToUser();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _userData.close();
    _isLoading.close();
    super.dispose();
  }

  void _listenToUser() async {
    // Cancel any previous subscription
    await _userSub?.cancel();
    _userSub = null;

    final user = _auth.currentUser;
    if (user == null || !mounted) {
      if (!mounted) return;
      if (!_isLoading.isClosed) _isLoading.add(false);
      return;
    }

    // Show loading
    if (!_isLoading.isClosed) _isLoading.add(true);

    _userSub = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .debounceTime(const Duration(milliseconds: 300))
        .listen(
      (doc) {
        if (!mounted) return;

        final Map<String, dynamic> newData;
        if (!doc.exists) {
          newData = {
            'fullName': 'User',
            'email': user.email ?? '',
            'phone': user.phoneNumber ?? '',
            'profileImage': '',
          };
        } else {
          final data = doc.data()!;
          newData = {
            'fullName': (data['fullName'] ?? 'User') as String,
            'email': (data['email'] ?? user.email ?? '') as String,
            'phone': (data['phone'] ?? user.phoneNumber ?? '') as String,
            'profileImage': (data['profileImage'] ?? '') as String,
          };
        }

        // SAFE: Only add if not closed
        if (!_userData.isClosed) _userData.add(newData);
        if (!_isLoading.isClosed) _isLoading.add(false);
      },
      onError: (e) {
        debugPrint('User stream error: $e');
        if (mounted && !_isLoading.isClosed) _isLoading.add(false);
      },
    );
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
          title: const Text('Account', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, thickness: 1, color: Colors.white)),
        ),
        body: StreamBuilder<bool>(
          stream: _isLoading,
          builder: (context, loadingSnap) {
            final isLoading = loadingSnap.data ?? true;
            return StreamBuilder<Map<String, dynamic>>(
              stream: _userData,
              builder: (context, userSnap) {
                final data = userSnap.data ?? {};
                final fullName = data['fullName'] ?? 'User';
                final profileImage = data['profileImage'] ?? '';

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile Row
                      Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.grey,
                                backgroundImage: profileImage.isNotEmpty ? NetworkImage(profileImage) : null,
                                child: profileImage.isEmpty
                                    ? const Icon(Icons.person, color: Colors.white, size: 40)
                                    : null,
                              ),
                              if (isLoading)
                                const Positioned.fill(
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: isLoading
                                ? const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _SkeletonLine(width: 120),
                                      SizedBox(height: 4),
                                      _SkeletonLine(width: 80),
                                    ],
                                  )
                                : Text(
                                    fullName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Menu Items
                      _menuTile('My Profile', onTap: () async {
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyProfileScreen(
                              fullName: data['fullName'] ?? '',
                              email: data['email'] ?? '',
                              phone: data['phone'] ?? '',
                              profileImage: data['profileImage'] ?? '',
                            ),
                          ),
                        );

                        if (updated == true && mounted) {
                          HapticFeedback.lightImpact();
                          _listenToUser(); // Safe: recreates listener
                        }
                      }),
                      _menuTile('Notifications', onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                      }),
                      _menuTile('Order History', onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasesScreen(currentIndex: 2)));
                      }),

                      // Push logout to bottom
                      const Flexible(child: SizedBox(height: 32)),

                      // Log Out Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white),
                            foregroundColor: null,
                          ),
                          onPressed: () async {
                            HapticFeedback.mediumImpact();
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
                );
              },
            );
          },
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: null,
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

class _SkeletonLine extends StatelessWidget {
  final double width;
  const _SkeletonLine({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      width: width,
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MyProfileScreen – WITH BEAUTIFUL EDITABLE PROFILE CARD
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
  final _firestore = firestore;
  final _storage = FirebaseStorage.instance;

  late final TextEditingController _fullNameController;
  final BehaviorSubject<String?> _profileImageUrl = BehaviorSubject.seeded(null);
  final BehaviorSubject<bool> _isUploading = BehaviorSubject.seeded(false);
  final BehaviorSubject<bool> _isSaving = BehaviorSubject.seeded(false);

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.fullName);
    _profileImageUrl.add(widget.profileImage.isNotEmpty ? widget.profileImage : null);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _profileImageUrl.close();
    _isUploading.close();
    _isSaving.close();
    super.dispose();
  }

  String _normalizeForComparison(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (s.startsWith('0')) s = '+63' + s.substring(1);
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
          toolbarWidgetColor: null,
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

    if (!_isUploading.isClosed) _isUploading.add(true);
    try {
      final ref = _storage.ref().child('profile_pictures/${user.uid}.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await _firestore.collection('users').doc(user.uid).update({'profileImage': url});

      if (!_profileImageUrl.isClosed) _profileImageUrl.add(url);
      if (!_isUploading.isClosed) _isUploading.add(false);
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated')));
    } catch (e) {
      if (!_isUploading.isClosed) _isUploading.add(false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed')));
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null || !mounted) return;

    final name = _fullNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
      return;
    }

    if (!_isSaving.isClosed) _isSaving.add(true);
    try {
      await _firestore.collection('users').doc(user.uid).update({'fullName': name});
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated!')));
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed')));
    } finally {
      if (!_isSaving.isClosed) _isSaving.add(false);
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
            // ── PROFILE PICTURE WITH CAMERA ICON & "TAP TO CHANGE" ──
            GestureDetector(
              onTap: pickAndCropImage,
              child: StreamBuilder<String?>(
                stream: _profileImageUrl,
                builder: (context, snap) {
                  final url = snap.data;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey,
                        backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
                        child: (url == null || url.isEmpty)
                            ? const Icon(Icons.person, size: 50, color: Colors.white)
                            : null,
                      ),
                      // Camera Icon (Always visible)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFF052238),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                        ),
                      ),
                      // "Tap to change" (Only when no image)
                      if (url == null || url.isEmpty)
                        Positioned(
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'Tap to change',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                      // Uploading Spinner
                      StreamBuilder<bool>(
                        stream: _isUploading,
                        builder: (context, upSnap) {
                          return upSnap.data == true
                              ? const Positioned.fill(
                                  child: Center(
                                    child: SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox();
                        },
                      ),
                    ],
                  );
                },
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
                  controller: _fullNameController,
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
                trailing: const Icon(Icons.lock, color: Colors.white),
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
            StreamBuilder<bool>(
              stream: _isSaving,
              builder: (context, saveSnap) {
                final isSaving = saveSnap.data ?? false;
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: null,
                      foregroundColor: const Color(0xFF052238),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: isSaving
                        ? const CircularProgressIndicator(color: Color(0xFF052238))
                        : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                );
              },
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