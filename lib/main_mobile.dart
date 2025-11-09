// lib/main_mobile.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:daligas/firebase_options.dart';
import 'package:daligas/screens/welcome_screen.dart';
import 'package:daligas/screens/signup_screen.dart';
import 'package:daligas/screens/signin_screen.dart';
import 'package:daligas/screens/chat_screen.dart';
import 'package:daligas/screens/order_details_screen.dart';
import 'package:daligas/screens/home_screen.dart'; // ← ADD THIS

// ------------------------------------------------------------
// Global Navigator Key
// ------------------------------------------------------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ------------------------------------------------------------
// Local Notifications Setup
// ------------------------------------------------------------
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'daligas_channel',
  'DaliGas Notifications',
  description: 'Channel for DaliGas notifications',
  importance: Importance.high,
);

// ------------------------------------------------------------
// Background Notification Handler
// ------------------------------------------------------------
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) print("Background message: ${message.notification?.title}");
}

// ------------------------------------------------------------
// MAIN FUNCTION
// ------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
  );

  FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

  // Firebase Messaging
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Local Notifications
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (details) {
      final payload = details.payload;
      if (payload != null) {
        final data = Map<String, dynamic>.from(
            payload.split('|').asMap().map((k, v) => MapEntry(v.split(':')[0], v.split(':')[1])));
        _handleNotificationTap(RemoteMessage(data: data));
      }
    },
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // === SAVE FCM TOKEN ON LOGIN (Auth State Listener) ===
  FirebaseAuth.instance.authStateChanges().listen((User? user) async {
    if (user != null) {
      await saveFcmToken(user);
    }
  });

  // === TOKEN REFRESH LISTENER ===
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await saveFcmToken(user, newToken: newToken);
    }
  });

  // === FOREGROUND NOTIFICATIONS ===
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final notification = message.notification;
    final data = message.data;
    final type = data['type'] ?? 'general';

    // Determine collection
    String collection = 'users';
    final empDoc = await FirebaseFirestore.instance
        .collection('employees')
        .doc(user.uid)
        .get();
    if (empDoc.exists && empDoc.data()?['role'] == 'employee') {
      collection = 'employees';
    }

    final parentCollection = FirebaseFirestore.instance.collection(collection);
    final userDoc = await parentCollection.doc(user.uid).get();
    final docData = userDoc.data() as Map<String, dynamic>?;
    final prefs = (docData?['notifications'] as Map<String, dynamic>?) ?? {};

    bool allowed = false;
    if (type == 'order' && (prefs['orderUpdates'] ?? true)) allowed = true;
    if (type == 'delivery' && (prefs['deliveryReminders'] ?? true)) allowed = true;
    if (type == 'chat' && (prefs['chatMessages'] ?? true)) allowed = true;
    if (type == 'promo' && (prefs['promotions'] ?? false)) allowed = true;
    if (type == 'general') allowed = true;

    if (!allowed) {
      if (kDebugMode) print("Notification blocked: $type");
      return;
    }

    if (notification != null) {
      final payload = 'type:${data['type']}|chatId:${data['chatId'] ?? ''}|orderId:${data['orderId'] ?? ''}';
      await flutterLocalNotificationsPlugin.show(
        0,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: payload,
      );

      final String? messageId = message.messageId;
      if (messageId != null) {
        final existing = await parentCollection
            .doc(user.uid)
            .collection('inAppNotifications')
            .where('messageId', isEqualTo: messageId)
            .limit(1)
            .get();

        if (existing.docs.isEmpty) {
          await parentCollection
              .doc(user.uid)
              .collection('inAppNotifications')
              .add({
            'title': notification.title,
            'body': notification.body,
            'type': type,
            'chatId': data['chatId'],
            'orderId': data['orderId'],
            'messageId': messageId,
            'timestamp': FieldValue.serverTimestamp(),
            'seen': false,
          });
        }
      }
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

  runApp(const MyApp());
}

// ------------------------------------------------------------
// Handle Notification Tap
// ------------------------------------------------------------
Future<void> _handleNotificationTap(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'];
  final context = navigatorKey.currentContext;
  if (context == null) return;

  if (type == 'message' && data['chatId'] != null) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: data['chatId'],
          title: data['title'] ?? 'Chat',
          isEmployee: false,
        ),
      ),
    );
  } else if (type == 'order' && data['orderId'] != null) {
  final orderId = data['orderId'];
  final context = navigatorKey.currentContext;
  if (context == null) return;

  try {
    final orderDoc = await FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId)
        .get();

    if (!orderDoc.exists) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order not found')),
        );
      }
      return;
    }

    final orderData = orderDoc.data()!;

    final itemsSnap = await FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId)
        .collection('items')
        .get();

    final items = itemsSnap.docs.map((doc) => doc.data()).toList();

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(
          orderId: orderId,
          orderData: orderData,
          items: items,
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load order: $e')),
      );
    }
  }
}
}

// ------------------------------------------------------------
// Save FCM Token
// ------------------------------------------------------------
Future<void> saveFcmToken(User user, {String? newToken}) async {
  final token = newToken ?? await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  String collection = 'users';
  String? role;

  final empDoc = await FirebaseFirestore.instance.collection('employees').doc(user.uid).get();
  if (empDoc.exists) {
    role = empDoc.data()?['role'] as String?;
    if (role == 'employee') collection = 'employees';
  } else {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      role = userDoc.data()?['role'] as String?;
      if (role == 'employee') collection = 'employees';
    }
  }

  final ref = FirebaseFirestore.instance.collection(collection).doc(user.uid);
  final doc = await ref.get();

  try {
    final Map<String, dynamic> data = {
      'fcmToken': token,
      'lastActive': FieldValue.serverTimestamp(),
    };

    if (!doc.exists) {
      data.addAll({
        'uid': user.uid,
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
        'notifications': {
          'orderUpdates': true,
          'deliveryReminders': true,
          'chatMessages': true,
          'promotions': false,
        },
      });
      if (collection == 'employees') {
        data['role'] = 'employee';
        data['name'] = user.displayName ?? 'Delivery Staff';
      }
    }

    await ref.set(data, SetOptions(merge: true));
    if (kDebugMode) print("FCM Token saved for $collection: ${user.uid}");
  } catch (e) {
    if (kDebugMode) print("Failed to save FCM token: $e");
  }
}

// ------------------------------------------------------------
// MAIN APP WITH AUTH WRAPPER (PERSISTENT LOGIN)
// ------------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'DALIGAS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthWrapper(), // ← REPLACES WelcomeScreen
      routes: {
        '/signin': (context) => const SignInScreen(),
        '/signup': (context) => const SignUpScreen(),
      },
    );
  }
}

// ------------------------------------------------------------
// AUTH WRAPPER: DECIDES WHERE TO GO BASED ON LOGIN STATE
// ------------------------------------------------------------
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still checking
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0D2236),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        // User is logged in → go to Home
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // No user → show Welcome
        return const WelcomeScreen();
      },
    );
  }
}