// lib/main_mobile.dart
import 'dart:convert'; // ← ADDED FOR JSON

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
import 'package:daligas/screens/home_screen.dart';
import 'package:daligas/screens/employee_orders_screen.dart';

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
      if (payload != null && payload.isNotEmpty) {
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          final remoteMessage = RemoteMessage(data: data);
          _handleNotificationTap(remoteMessage);
        } catch (e) {
          if (kDebugMode) print("Failed to parse notification payload: $e");
        }
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
    if (type == 'message' && (prefs['chatMessages'] ?? true)) allowed = true;
    if (type == 'promo' && (prefs['promotions'] ?? false)) allowed = true;
    if (type == 'general') allowed = true;

    if (!allowed) {
      if (kDebugMode) print("Notification blocked: $type");
      return;
    }

    if (notification != null) {
      // Use JSON payload
      final payload = jsonEncode({
        'type': type,
        'chatId': data['chatId'] ?? '',
        'orderId': data['orderId'] ?? '',
        'title': data['title'] ?? notification.title,
      });

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
// Handle Notification Tap (UPDATED FOR CHAT + EMPLOYEE)
// ------------------------------------------------------------
Future<void> _handleNotificationTap(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'];
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return;

  // === CHAT MESSAGE NOTIFICATION ===
  if (type == 'message' && data['chatId'] != null) {
    final chatId = data['chatId'] as String;
    final orderId = data['orderId'] is String ? data['orderId'] as String : null;
    final title = data['title'] as String? ?? 'Chat';

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    bool isEmployee = false;
    final empDoc = await FirebaseFirestore.instance
        .collection('employees')
        .doc(user.uid)
        .get();
    if (empDoc.exists && empDoc.data()?['role'] == 'employee') {
      isEmployee = true;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          title: title,
          isEmployee: isEmployee,
          orderId: orderId,
        ),
      ),
    );
    return;
  }

  // === ORDER NOTIFICATION ===
  if (type == 'order' && data['orderId'] != null) {
    final orderId = data['orderId'] as String;

    try {
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();

      if (!orderDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order not found')),
        );
        return;
      }

      final orderData = orderDoc.data()!;
      final itemsSnap = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .get();
      final items = itemsSnap.docs.map((doc) => doc.data()).toList();

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load order: $e')),
      );
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

  final empDoc = await FirebaseFirestore.instance
      .collection('employees')
      .doc(user.uid)
      .get();
  if (empDoc.exists) {
    role = empDoc.data()?['role'] as String?;
    if (role == 'employee') collection = 'employees';
  } else {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
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
// MAIN APP
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
      home: const AuthWrapper(),
      routes: {
        '/signin': (context) => const SignInScreen(),
        '/signup': (context) => const SignUpScreen(),
      },
    );
  }
}

// ------------------------------------------------------------
// AUTH WRAPPER – ROLE-AWARE
// ------------------------------------------------------------
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<Widget> _getHomeScreen(User user) async {
    final empDoc = await FirebaseFirestore.instance
        .collection('employees')
        .doc(user.uid)
        .get();

    if (empDoc.exists && (empDoc.data()?['role'] as String?) == 'employee') {
      return const EmployeeOrdersScreen();
    }

    return const HomeScreen();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0D2236),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;

          return FutureBuilder<Widget>(
            future: _getHomeScreen(user),
            builder: (context, homeSnapshot) {
              if (homeSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: Color(0xFF0D2236),
                  body: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );
              }

              if (homeSnapshot.hasData) {
                return homeSnapshot.data!;
              }

              return const HomeScreen();
            },
          );
        }

        return const WelcomeScreen();
      },
    );
  }
}