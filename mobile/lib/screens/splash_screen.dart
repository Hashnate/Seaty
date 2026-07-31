import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF0A2540), Color(0xFF1E3A8A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/app_logo.png',
                      height: 220,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.directions_bus_rounded,
                        size: 90,
                        color: Color(0xFF60A5FA),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 800.ms, curve: Curves.easeOut)
                        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.0, 1.0), duration: 1000.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 16),
                    Text(
                      'LUXURY TRANSPORT',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF93C5FD),
                        letterSpacing: 3.5,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 500.ms, duration: 600.ms)
                        .slideY(begin: 0.3, end: 0, delay: 500.ms, duration: 600.ms),
                  ],
                ),
              ),
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFF60A5FA).withValues(alpha: 0.8),
                      ),
                    ),
                  ).animate().fadeIn(delay: 800.ms),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
