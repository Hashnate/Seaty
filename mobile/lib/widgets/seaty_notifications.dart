import 'package:flutter/material.dart';

// =====================================================================
// CUSTOM NOTIFICATION MANAGER (Toast / SnackBar Replacement)
// =====================================================================
class SeatyNotifications {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();

    final Color bgColor = isError
        ? const Color(0xFFEF4444) // Soft Red
        : isWarning
        ? const Color(0xFFF59E0B) // Amber/Orange
        : const Color(0xFF10B981); // Emerald Green

    final IconData icon = isError
        ? Icons.error_outline_rounded
        : isWarning
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: duration,
      ),
    );
  }
}
