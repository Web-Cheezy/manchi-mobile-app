import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manchi_app/features/services/backend_service.dart';
import 'package:manchi_app/utils/app_meta.dart';

const String _storageKey = 'saved_notifications';

/// One saved notification for the in-app list.
class SavedNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String? orderId;
  final String? type;

  SavedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.orderId,
    this.type,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'isRead': isRead,
        'orderId': orderId,
        'type': type,
      };

  static SavedNotification fromJson(Map<String, dynamic> json) {
    return SavedNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
      orderId: json['orderId'] as String?,
      type: json['type'] as String?,
    );
  }

  /// Parse a notification from backend API (snake_case: created_at, is_read, order_id).
  static SavedNotification fromBackendJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final title = json['title']?.toString() ?? '';
    final body = json['body']?.toString() ?? '';
    final createdAtStr = json['created_at']?.toString() ?? json['createdAt']?.toString() ?? '';
    final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
    final isRead = json['is_read'] as bool? ?? json['isRead'] as bool? ?? false;
    final orderId = json['order_id']?.toString() ?? json['orderId']?.toString();
    final type = json['type']?.toString();
    return SavedNotification(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      isRead: isRead,
      orderId: orderId,
      type: type,
    );
  }
}

/// Handles FCM and local notifications. Order-created and order-status-change
/// notifications are sent from the backend; this service registers the device
/// token and displays incoming messages. Saves notifications locally for the Notifications tab.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  List<SavedNotification> _list = [];
  VoidCallback? onNotificationsUpdated;
  void Function(String payload)? onNotificationOpened;
  bool _storageLoaded = false;
  String? _cachedFcmToken;

  /// Must match backend FCM Android channel id in AndroidManifest metadata.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'order_updates',
    'Order updates',
    description: 'Notifications for order status and new orders',
    importance: Importance.high,
    playSound: true,
  );

  bool _initialized = false;

  static String get _platformLabel => Platform.isIOS ? 'ios' : 'android';

  static bool _isPushAuthorized(NotificationSettings settings) {
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Call from main() after WidgetsFlutterBinding.ensureInitialized().
  /// Requires Firebase to be initialized first (Firebase.initializeApp()).
  Future<void> initialize() async {
    if (_initialized) return;

    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidInit = AndroidInitializationSettings('@drawable/ic_manchi_notification');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _local.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      final notification = initialMessage.notification;
      final data = initialMessage.data;
      if (notification != null) {
        await _saveAndNotify(
          title: notification.title ?? 'Order update',
          body: notification.body ?? '',
          orderId: data['order_id']?.toString(),
          type: data['type']?.toString(),
        );
      }
      _handleNotificationPayload(initialMessage.data);
    }

    if (Platform.isIOS) {
      await _fcm.setAutoInitEnabled(true);
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _fcm.onTokenRefresh.listen(_registerToken);

    if (_isPushAuthorized(settings)) {
      final token = await _getTokenWithRetries();
      await _registerToken(token);
    }

    _initialized = true;
  }

  Future<String?> _getTokenWithRetries() async {
    if (Platform.isIOS) {
      for (var i = 0; i < 5; i++) {
        final apns = await _fcm.getAPNSToken();
        if (apns != null && apns.isNotEmpty) break;
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    for (var i = 0; i < 6; i++) {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) return token;
      await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
    return null;
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _navigateFromPayload(payload);
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification != null) {
      final data = message.data;
      await _saveAndNotify(
        title: notification.title ?? 'Order update',
        body: notification.body ?? '',
        orderId: data['order_id']?.toString(),
        type: data['type']?.toString(),
      );
      await _local.show(
        id: notification.hashCode,
        title: notification.title ?? 'Order update',
        body: notification.body ?? '',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            icon: '@drawable/ic_manchi_notification',
            color: const Color(0xFFE02B27),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: data['order_id'] ?? data['route'] ?? '',
      );
    }
  }

  Future<void> _onMessageOpenedApp(RemoteMessage message) async {
    final notification = message.notification;
    if (notification != null) {
      final data = message.data;
      await _saveAndNotify(
        title: notification.title ?? 'Order update',
        body: notification.body ?? '',
        orderId: data['order_id']?.toString(),
        type: data['type']?.toString(),
      );
    }
    _handleNotificationPayload(message.data);
  }

  void _handleNotificationPayload(Map<String, dynamic> data) {
    final orderId = data['order_id'];
    final route = data['route'] ?? 'order_history';
    _navigateFromPayload(orderId?.toString() ?? route);
  }

  void _navigateFromPayload(String payload) {
    try {
      if (onNotificationOpened != null) {
        onNotificationOpened!(payload);
      }
    } catch (_) {}
  }

  Future<void> _registerToken(String? token) async {
    if (token == null || token.isEmpty) return;

    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (!_isPushAuthorized(settings)) return;

    _cachedFcmToken = token;
    final user = await BackendService.getCurrentUser();
    if (user?['id'] == null) return;

    final deviceId = await AppMeta.deviceInstallId();
    await BackendService.registerFcmToken(
      fcmToken: token,
      platform: _platformLabel,
      deviceId: deviceId,
      appVersion: AppMeta.version,
    );
  }

  /// Call after login and when notification permission is granted.
  Future<void> refreshTokenRegistration() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (!_isPushAuthorized(settings)) return;

    final token = await _getTokenWithRetries();
    await _registerToken(token ?? _cachedFcmToken);
  }

  /// Remove token from backend on logout.
  Future<void> unregisterToken() async {
    final token = _cachedFcmToken ?? await _fcm.getToken();
    if (token == null || token.isEmpty) return;
    await BackendService.unregisterFcmToken(token);
    _cachedFcmToken = null;
  }

  // --- Saved notifications for in-app tab ---

  Future<void> _loadFromStorage() async {
    if (_storageLoaded) return;
    _storageLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_storageKey);
      if (json != null) {
        final list = jsonDecode(json) as List<dynamic>?;
        if (list != null) {
          _list = list
              .map((e) => SavedNotification.fromJson(e as Map<String, dynamic>))
              .toList();
          _list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
      }
    } catch (_) {
      _list = [];
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_list.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, json);
    } catch (_) {}
    onNotificationsUpdated?.call();
  }

  Future<void> _saveAndNotify({
    required String title,
    required String body,
    String? orderId,
    String? type,
  }) async {
    await _loadFromStorage();
    final id = '${DateTime.now().millisecondsSinceEpoch}';
    _list.insert(
      0,
      SavedNotification(
        id: id,
        title: title,
        body: body,
        createdAt: DateTime.now(),
        orderId: orderId,
        type: type,
      ),
    );
    await _persist();
  }

  /// Load saved notifications (newest first). Used by Notifications tab.
  Future<List<SavedNotification>> getNotifications() async {
    await _loadFromStorage();
    return List.unmodifiable(_list);
  }

  /// Mark a notification as read.
  Future<void> markAsRead(String id) async {
    await _loadFromStorage();
    final index = _list.indexWhere((n) => n.id == id);
    if (index < 0) return;
    _list[index] = SavedNotification(
      id: _list[index].id,
      title: _list[index].title,
      body: _list[index].body,
      createdAt: _list[index].createdAt,
      isRead: true,
      orderId: _list[index].orderId,
      type: _list[index].type,
    );
    await _persist();
  }

  /// Optional: clear all saved notifications.
  Future<void> clearAll() async {
    _list = [];
    _storageLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
    onNotificationsUpdated?.call();
  }
}

/// Must be top-level. When the message includes a "notification" block,
/// FCM shows the system notification automatically in background.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
