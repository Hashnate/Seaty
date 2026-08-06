import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:seaty/widgets/seaty_bus_loading.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/screens/auth_screen.dart';

// =====================================================================
// DART-LEVEL SPLASH SCREEN (Shows on every Hot Restart)
// =====================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _controller.forward();

    Timer(const Duration(milliseconds: 2800), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          SeatyPageRoute(page: const AuthWrapper()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.white,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/app_logo.png',
                      height: 170,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.directions_bus_rounded,
                        size: 90,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'LUXURY TRANSPORT',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF2563EB),
                        letterSpacing: 3.5,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 300.ms, duration: 500.ms)
                        .slideY(begin: 0.2, end: 0, delay: 300.ms, duration: 500.ms),
                    const SizedBox(height: 24),
                    const SeatyBusLoadingIndicator.small()
                        .animate()
                        .fadeIn(delay: 500.ms),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
