import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:manchi_app/features/pages/home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Heartbeat Animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _redirect();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redirect() async {
    // Wait for animation and "cool" duration
    await Future.delayed(const Duration(milliseconds: 500));
    HapticFeedback.mediumImpact(); // Vibration
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Always redirect to HomePage, regardless of auth status
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const HomePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoAsset = isDark ? 'assets/darkmanchi.png' : 'assets/lightmanchi.png';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: ClipOval(
            child: Container(
              width: 150,
              height: 150,
              color: isDark ? Colors.black : Colors.white,
              child: Image.asset(
                logoAsset,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
