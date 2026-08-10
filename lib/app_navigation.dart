import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Called when user opens the app from a push notification. Set from main.dart
/// to push OrderHistoryPage (or a specific order).
void Function(String payload)? onNotificationOpened;
