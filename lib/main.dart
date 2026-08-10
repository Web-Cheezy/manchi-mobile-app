import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_navigation.dart';
import 'features/services/backend_service.dart';
import 'features/services/notification_service.dart';
import 'themes/app_theme.dart';
import 'themes/theme_provider.dart';
import 'features/pages/splash_page.dart';
import 'features/pages/order_history_page.dart';
import 'features/data/cart_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  BackendService.ensureConfigured();

  try {
    await Firebase.initializeApp();
    final notifService = NotificationService();
    await notifService.initialize();
    notifService.onNotificationOpened = (payload) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const OrderHistoryPage()),
      );
    };
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Firebase/Notifications init skipped');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Manchi',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          home: const SplashPage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
