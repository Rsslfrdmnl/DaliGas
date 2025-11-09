import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cross_file/cross_file.dart';   // for XFile → File conversion
import 'employee_orders_screen.dart';
import 'package:daligas/screens/welcome_screen.dart';
import 'package:daligas/screens/notifications_screen.dart';

/// Firestore & Storage path constants
class FirestorePaths {
  static const String employees = 'employees';
  static const String employeePictures = 'employee_pictures';
}

class EmployeeAccountScreen extends StatefulWidget {
  final int currentIndex;
  const EmployeeAccountScreen({super.key, this.currentIndex = 1});

  @override
  State<EmployeeAccountScreen> createState() => _EmployeeAccountScreenState();
}

class _EmployeeAccountScreenState extends State<EmployeeAccountScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String name = '';
  String email = '';
  String phone = '';
  String profileImage = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchEmployeeData();
  }

  Future<void> fetchEmployeeData() async {
    setState(() => isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() => isLoading = false);
        return;
      }
      final doc = await _firestore
          .collection(FirestorePaths.employees)
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          name = (data['name'] ?? '') as String;
          email = (data['email'] ?? user.email ?? '') as String;
          phone = (data['phone'] ?? user.phoneNumber ?? '') as String;
          profileImage = (data['profileImage'] ?? '') as String;
          isLoading = false;
        });
      } else {
        setState(() {
          name = user.displayName ?? user.email ?? 'Employee';
          email = user.email ?? '';
          phone = user.phoneNumber ?? '';
          profileImage = '';
          isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('fetchEmployeeData error: $e');
      setState(() => isLoading = false);
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
    return Scaffold(
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
                        backgroundImage: profileImage.isNotEmpty
                            ? NetworkImage(profileImage)
                            : null,
                        child: profileImage.isEmpty
                            ? const Icon(Icons.person, color: Colors.white, size: 40)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          name.isNotEmpty ? name : 'Employee',
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
                    final refreshed = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EmployeeProfileScreen(
                          name: name,
                          email: email,
                          phone: phone,
                          profileImage: profileImage,
                        ),
                      ),
                    );
                    if (refreshed == true) fetchEmployeeData();
                  }),
                  _menuTile('Notifications', onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
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
                      child: const Text('Log Out',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
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
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const EmployeeOrdersScreen(currentIndex: 0),
                    transitionDuration: Duration.zero,
                  ),
                );
                break;
              case 1:
                break;
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping_outlined),
              activeIcon: Icon(Icons.local_shipping, color: Color(0xFF0D2236)),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person, color: Color(0xFF0D2236)),
              label: '',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EmployeeProfileScreen
// ─────────────────────────────────────────────────────────────────────────────

class EmployeeProfileScreen extends StatefulWidget {
  final String name;
  final String email;
  final String phone;
  final String profileImage;

  const EmployeeProfileScreen({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.profileImage,
  });

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  late TextEditingController nameController;
  String? profileImageUrl;
  bool isUploading = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    profileImageUrl = widget.profileImage;
    nameController = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> pickAndCropImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image selection cancelled or permission denied')),
      );
      return;
    }

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: const Color(0xFF052238),
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,   // <-- fixed
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Crop Image'),
      ],
    );
    if (cropped == null) return;

    // `cropped` is a `CroppedFile` (which is an XFile)
    await uploadCroppedImage(cropped);
  }

  Future<void> uploadCroppedImage(CroppedFile croppedFile) async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => isUploading = true);
    try {
      // ---- COMPRESS ----
      final XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
        croppedFile.path,
        '${croppedFile.path}_compressed.jpg',
        quality: 85,
        minWidth: 800,
        minHeight: 800,
      );

      if (compressedXFile == null) throw Exception('Compression failed');

      // Convert XFile → File for Firebase Storage
      final File compressedFile = File(compressedXFile.path);

      final ref = _storage
          .ref()
          .child('${FirestorePaths.employeePictures}/${user.uid}.jpg');

      // ---- DELETE OLD IMAGE ----
      if (profileImageUrl != null && profileImageUrl!.isNotEmpty) {
        try {
          await _storage.refFromURL(profileImageUrl!).delete();
        } catch (_) {
          // ignore if old file is already gone
        }
      }

      // ---- UPLOAD ----
      final uploadTask = ref.putFile(compressedFile);
      await uploadTask.whenComplete(() => null);
      final url = await ref.getDownloadURL();

      // ---- UPDATE FIRESTORE ----
      await _firestore
          .collection(FirestorePaths.employees)
          .doc(user.uid)
          .update({'profileImage': url});

      setState(() {
        profileImageUrl = url;
        isUploading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated')),
      );
    } catch (e) {
      setState(() => isUploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final trimmedName = nameController.text.trim();
    if (trimmedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => isSaving = true);
    try {
      await _firestore
          .collection(FirestorePaths.employees)
          .doc(user.uid)
          .update({'name': trimmedName});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!')),
      );
      Navigator.pop(context, true); // signal refresh
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    final emailToShow = widget.email.isNotEmpty ? widget.email : (currentUser?.email ?? '');
    final phoneToShow = widget.phone.isNotEmpty ? widget.phone : (currentUser?.phoneNumber ?? '');

    return Scaffold(
      backgroundColor: const Color(0xFF052238),
      appBar: AppBar(
        backgroundColor: const Color(0xFF052238),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Profile',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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

            // Full Name (editable)
            Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),

            // Email (read-only)
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

            // Phone (read-only)
            Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: ListTile(
                title: const Text('Phone', style: TextStyle(fontSize: 12, color: Colors.black54)),
                subtitle: Text(phoneToShow, style: const TextStyle(color: Colors.black87)),
                trailing: const Icon(Icons.lock, color: Colors.grey),
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
          ],
        ),
      ),
    );
  }
}