import 'package:flutter/material.dart';

// =====================================================================
// CUSTOM NOTIFICATION MANAGER (WhatsApp Style Toast System)
// =====================================================================
class SeatyNotifications {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
    bool isInfo = false,
    Color? customColor,
    IconData? customIcon,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();

    // WhatsApp Signature Accent Colors
    final Color iconColor = customColor ??
        (isError
            ? const Color(0xFFF87171)  // Soft Red
            : isWarning
                ? const Color(0xFFFBBF24)  // Warm Amber
                : isInfo
                    ? const Color(0xFF38BDF8)  // Sky Blue
                    : const Color(0xFF00A884)); // WhatsApp Signature Emerald Green

    final IconData icon = customIcon ??
        (isError
            ? Icons.error_outline_rounded
            : isWarning
                ? Icons.warning_amber_rounded
                : isInfo
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_rounded);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        padding: EdgeInsets.zero,
        duration: duration,
        content: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111B21), // WhatsApp Dark Theme Background
            borderRadius: BorderRadius.circular(28), // Sleek Capsule Pill Shape
            border: Border.all(
              color: const Color(0xFF222D34), // WhatsApp Dark Border
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFE9EDEF), // WhatsApp Dark Text Color
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


