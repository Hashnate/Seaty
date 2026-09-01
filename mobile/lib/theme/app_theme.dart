import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart'; // ignore: unnecessary_import
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      primaryColor: AppColors.primaryNavy,
      hintColor: AppColors.primaryBlue,
      cardColor: AppColors.surfaceLight,
      fontFamily: GoogleFonts.poppins().fontFamily,
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        displayLarge: const TextStyle(letterSpacing: 0.15),
        displayMedium: const TextStyle(letterSpacing: 0.15),
        displaySmall: const TextStyle(letterSpacing: 0.15),
        headlineLarge: const TextStyle(letterSpacing: 0.15),
        headlineMedium: const TextStyle(letterSpacing: 0.15),
        headlineSmall: const TextStyle(letterSpacing: 0.15),
        titleLarge: const TextStyle(letterSpacing: 0.15),
        titleMedium: const TextStyle(letterSpacing: 0.15),
        titleSmall: const TextStyle(letterSpacing: 0.15),
        bodyLarge: const TextStyle(letterSpacing: 0.15),
        bodyMedium: const TextStyle(letterSpacing: 0.15),
        bodySmall: const TextStyle(letterSpacing: 0.15),
        labelLarge: const TextStyle(letterSpacing: 0.15),
        labelMedium: const TextStyle(letterSpacing: 0.15),
        labelSmall: const TextStyle(letterSpacing: 0.15),
      ),
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryNavy,
        secondary: AppColors.primaryBlue,
        surface: AppColors.surfaceLight,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 8,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Custom smooth page route transition helper (Slide + Fade)
class SeatyPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SeatyPageRoute({required this.page, super.settings})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curveAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0.0),
                end: Offset.zero,
              ).animate(curveAnimation),
              child: FadeTransition(
                opacity: curveAnimation,
                child: child,
              ),
            );
          },
        );
}
