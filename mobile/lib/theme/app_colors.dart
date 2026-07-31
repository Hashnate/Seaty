import 'package:flutter/material.dart';

/// Centralized Color System for Seaty Luxury Bus Transport Mobile App
class AppColors {
  AppColors._();

  // Primary Brand Colors
  static const Color primaryNavy = Color(0xFF0A2540); // Deep Brand Navy
  static const Color primaryBlue = Color(0xFF2563EB); // Vibrant Electric Blue
  static const Color secondaryBlue = Color(0xFF3B82F6); // Soft Royal Blue
  static const Color accentIceBlue = Color(0xFF93C5FD); // Ice Blue accent
  static const Color highlightOrange = Color(0xFFFF8A50); // Coral Accent

  // Background & Surfaces
  static const Color backgroundLight = Color(0xFFF8FAFC); // Slate off-white
  static const Color surfaceLight = Colors.white;
  static const Color surfaceSubtle = Color(0xFFF1F5F9);
  
  static const Color backgroundDark = Color(0xFF0F172A); // Midnight Slate
  static const Color surfaceDark = Color(0xFF1E293B);

  // Borders & Dividers
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFCBD5E1);
  static const Color borderDark = Color(0xFF334155);

  // Status & Feedback Colors
  static const Color success = Color(0xFF10B981); // Emerald Green
  static const Color warning = Color(0xFFF59E0B); // Amber Warning
  static const Color error = Color(0xFFEF4444); // Crimson Error
  static const Color info = Color(0xFF3B82F6); // Info Blue
  static const Color seatHeld = Color(0xFFD97706); // Warm Amber for Held Seats
  static const Color seatFemale = Color(0xFFE11D48); // Rose for Female Reserved

  // Neutral Text Colors
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textLight = Colors.white;

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryNavy, Color(0xFF1E3A8A), primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient vibrantHeroGradient = LinearGradient(
    colors: [primaryNavy, Color(0xFF1E40AF), primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [primaryBlue, Color(0xFF60A5FA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassOverlayGradient = LinearGradient(
    colors: [Color(0xE60F172A), Color(0xCC1E293B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
