import 'package:flutter/material.dart';

// =====================================================================
// CUSTOM SEAT WIDGET
// =====================================================================
class Animated3DSeat extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isBooked;
  final bool isHeld;
  final String gender;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const Animated3DSeat({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isBooked,
    required this.isHeld,
    required this.gender,
    required this.width,
    required this.height,
    this.onTap,
  });

  @override
  State<Animated3DSeat> createState() => _Animated3DSeatState();
}

class _Animated3DSeatState extends State<Animated3DSeat>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.12),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.12, end: 1.0),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant Animated3DSeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color borderColor;
    Color cushionFillColor;
    Color textColor;
    IconData? genderIcon;

    if (widget.isBooked) {
      final String g = widget.gender.toLowerCase();
      if (g == 'male') {
        borderColor = const Color(0xFF2563EB); // Male Blue
        cushionFillColor = const Color(0xFF2563EB);
        textColor = Colors.white;
      } else if (g == 'female') {
        borderColor = const Color(0xFFEC4899); // Female Pink
        cushionFillColor = const Color(0xFFEC4899);
        textColor = Colors.white;
      } else {
        borderColor = const Color(0xFF475569);
        cushionFillColor = const Color(0xFF475569);
        textColor = Colors.white;
      }
    } else if (widget.isHeld) {
      borderColor = const Color(0xFFD97706); // Amber
      cushionFillColor = const Color(0xFFD97706);
      textColor = Colors.white;
    } else if (widget.isSelected) {
      final String g = widget.gender.toLowerCase();
      if (g == 'female') {
        borderColor = const Color(0xFFEC4899); // Female Pink
        cushionFillColor = const Color(0xFFEC4899);
        textColor = Colors.white;
        genderIcon = Icons.woman_rounded;
      } else {
        borderColor = const Color(0xFF2563EB); // Male Blue
        cushionFillColor = const Color(0xFF2563EB);
        textColor = Colors.white;
        genderIcon = Icons.man_rounded;
      }
    } else {
      // Available seat
      borderColor = const Color(0xFF64748B); // Slate border
      cushionFillColor = Colors.white;
      textColor = const Color(0xFF0F172A);
    }

    // Strip non-numeric letters (e.g. S1 -> 1, 1A -> 1, Seat 1 -> 1)
    final String cleanLabel = widget.label.replaceAll(RegExp(r'[^0-9]'), '');
    final String displayLabel = cleanLabel.isNotEmpty ? cleanLabel : widget.label;

    return GestureDetector(
      onTap: (widget.isBooked || widget.isHeld) ? null : widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Full Seat Square
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cushionFillColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: borderColor,
                          width: widget.isSelected ? 1.8 : 1.3,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        displayLabel,
                        style: TextStyle(
                          fontSize: (widget.height * 0.38).clamp(11.0, 16.0),
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  // Gender Badge Icon (Shown ONLY for selected seats)
                  if (widget.isSelected && genderIcon != null)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            )
                          ],
                        ),
                        child: Icon(
                          genderIcon,
                          size: 11,
                          color: borderColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
