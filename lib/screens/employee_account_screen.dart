import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cross_file/cross_file.dart';
import 'package:rxdart/rxdart.dart'; // ← RxDart added
import 'employee_orders_screen.dart';
import 'package:daligas/screens/welcome_screen.dart';
import 'package:daligas/screens/notifications_screen.dart';
import 'package:flutter/services.dart'; // For SystemNavigator
import 'package:daligas/main_mobile.dart';

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

class _EmployeeAccountScreenState extends State<EmployeeAccountScreen>
    with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _firestore = firestore;

  String name = '';
  String email = '';
  String phone = '';
  String profileImage = '';
  bool isLoading = true;

  // Double back-press
  DateTime? _lastBackPress;

  // RxDart: Live unread notification count
  late final BehaviorSubject<int> _unreadCountSubject;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _unreadCountSubject = BehaviorSubject<int>.seeded(0);
    fetchEmployeeData();
    _listenToNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadCountSubject.close();
    super.dispose();
  }

  // Reactive: Listen to unread notifications
  void _listenToNotifications() {
    final user = _auth.currentUser;
    if (user == null) return;

    firestore
        .collection(FirestorePaths.employees)
        .doc(user.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _unreadCountSubject.add(snapshot.docs.length);
    });
  }

  Future<void> fetchEmployeeData() async {
    setState(() => isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() => isLoading = false);
        return;
      }
      final doc = await firestore
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

  Widget _menuTile(String title, {VoidCallback? onTap, Widget? trailing}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  // Double back-press to exit
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
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
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
    return true;
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
                    // Notifications with live badge
                    StreamBuilder<int>(
                      stream: _unreadCountSubject.stream,
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        return _menuTile(
                          'Notifications',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                            );
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (count > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    count > 99 ? '99+' : '$count',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        );
                      },
                    ),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EmployeeProfileScreen + PHONE VERIFICATION (UNCHANGED)
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
  final _firestore = firestore;
  final _storage = FirebaseStorage.instance;

  late TextEditingController nameController;
  String? profileImageUrl;
  bool isUploading = false;
  bool isSaving = false;
  bool isVerifyingPhone = false;

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

  Future<void> _verifyPhoneNumber() async {
    if (_isPhoneLinked) return;

    final rawPhone = widget.phone.isNotEmpty ? widget.phone : _auth.currentUser?.phoneNumber;
    if (rawPhone == null || rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number to verify')),
      );
      return;
    }

    final formattedPhone = _formatPhoneForFirebase(rawPhone);
    setState(() => isVerifyingPhone = true);

    String? verificationId;

    await _auth.verifyPhoneNumber(
      phoneNumber: formattedPhone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _linkPhoneCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => isVerifyingPhone = false);
        _showError('Verification failed: ${e.message}');
      },
      codeSent: (String vid, int? resendToken) async {
        verificationId = vid;
        setState(() => isVerifyingPhone = false);

        final smsCode = await _showOTPDialogWithSkip();
        if (smsCode == null) return;

        final credential = PhoneAuthProvider.credential(
          verificationId: vid,
          smsCode: smsCode,
        );
        await _linkPhoneCredential(credential);
      },
      codeAutoRetrievalTimeout: (String vid) {},
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _linkPhoneCredential(PhoneAuthCredential credential) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user signed in');

      await user.linkWithCredential(credential);

      await firestore
          .collection(FirestorePaths.employees)
          .doc(user.uid)
          .update({'phone': widget.phone.isNotEmpty ? widget.phone : user.phoneNumber});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone verified successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to link phone';
      if (e.code == 'credential-already-in-use') {
        message = 'This phone is already linked to another account';
      } else if (e.code == 'invalid-verification-code') {
        message = 'Invalid OTP. Please try again.';
      }
      _showError(message);
    } catch (e) {
      _showError('Error: $e');
    }
  }

  Future<String?> _showOTPDialogWithSkip() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D2236),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Verify Phone', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the 6-digit code sent to your phone',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                labelText: 'OTP Code',
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Skip', style: TextStyle(color: Colors.orange)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            child: const Text('Verify', style: TextStyle(color: Color(0xFF0D2236))),
          ),
        ],
      ),
    );
  }

  String _formatPhoneForFirebase(String phone) {
    String formatted = phone.trim();
    formatted = formatted.replaceAll(RegExp(r'\D'), '');
    if (formatted.startsWith('0')) {
      formatted = '+63${formatted.substring(1)}';
    } else if (formatted.startsWith('63')) {
      formatted = '+$formatted';
    } else if (!formatted.startsWith('+')) {
      formatted = '+63$formatted';
    }
    return formatted;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> pickAndCropImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image selection cancelled')),
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
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Crop Image'),
      ],
    );
    if (cropped == null) return;

    await uploadCroppedImage(cropped);
  }

  Future<void> uploadCroppedImage(CroppedFile croppedFile) async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => isUploading = true);
    try {
      final XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
        croppedFile.path,
        '${croppedFile.path}_compressed.jpg',
        quality: 85,
        minWidth: 800,
        minHeight: 800,
      );

      if (compressedXFile == null) throw Exception('Compression failed');
      final File compressedFile = File(compressedXFile.path);

      final ref = _storage
          .ref()
          .child('${FirestorePaths.employeePictures}/${user.uid}.jpg');

      if (profileImageUrl != null && profileImageUrl!.isNotEmpty) {
        try {
          await _storage.refFromURL(profileImageUrl!).delete();
        } catch (_) {}
      }

      await ref.putFile(compressedFile);
      final url = await ref.getDownloadURL();

      await firestore
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
      await firestore
          .collection(FirestorePaths.employees)
          .doc(user.uid)
          .update({'name': trimmedName});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!')),
      );
      Navigator.pop(context, true);
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
    final phoneLinked = _isPhoneLinked;

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
                  if (profileImageUrl == null || profileImageUrl!.isEmpty)
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
            
                  // Uploading Spinner (Overlay)
                  if (isUploading)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

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
                trailing: phoneLinked
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.help_outline, color: Colors.grey),
              ),
            ),

            if (!phoneLinked)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isVerifyingPhone ? null : _verifyPhoneNumber,
                    icon: isVerifyingPhone
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.verified_user, size: 20),
                    label: Text(isVerifyingPhone ? 'Sending OTP...' : 'Verify Phone'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

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

// --------------------------------//