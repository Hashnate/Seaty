import 'package:flutter/material.dart';

// =====================================================================
// CUSTOM ANIMATED 3D SEAT WIDGET
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
        tween: Tween<double>(begin: 1.0, end: 1.15),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0),
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
    Color armrestFillColor;
    Color bottomBarColor;
    Color bottomSegmentFillColor;
    Color textColor;
    IconData? genderIcon;

    if (widget.isBooked) {
      final String g = widget.gender.toLowerCase();
      if (g == 'male') {
        borderColor = const Color(0xFF0F2C59);
        cushionFillColor = const Color(0xFF0F2C59).withValues(alpha: 0.15);
        armrestFillColor = const Color(0xFF0F2C59).withValues(alpha: 0.25);
        bottomBarColor = const Color(0xFF0F2C59);
        bottomSegmentFillColor = const Color(0xFF0F2C59).withValues(alpha: 0.25);
        textColor = const Color(0xFF0F2C59);
        genderIcon = Icons.man_rounded;
      } else if (g == 'female') {
        borderColor = const Color(0xFFF472B6);
        cushionFillColor = const Color(0xFFF472B6).withValues(alpha: 0.15);
        armrestFillColor = const Color(0xFFF472B6).withValues(alpha: 0.25);
        bottomBarColor = const Color(0xFFF472B6);
        bottomSegmentFillColor = const Color(0xFFF472B6).withValues(alpha: 0.25);
        textColor = const Color(0xFFF472B6);
        genderIcon = Icons.woman_rounded;
      } else {
        borderColor = const Color(0xFF64748B);
        cushionFillColor = const Color(0xFFE2E8F0);
        armrestFillColor = const Color(0xFFE2E8F0);
        bottomBarColor = const Color(0xFF64748B);
        bottomSegmentFillColor = const Color(0xFFCBD5E1);
        textColor = const Color(0xFF64748B);
      }
    } else if (widget.isHeld) {
      borderColor = const Color(0xFFD97706); // Amber
      cushionFillColor = Colors.white;
      armrestFillColor = const Color(0xFFFDE68A);
      bottomBarColor = const Color(0xFFD97706);
      bottomSegmentFillColor = const Color(0xFFFDE68A);
      textColor = const Color(0xFFB45309);
    } else if (widget.isSelected) {
      final String g = widget.gender.toLowerCase();
      if (g == 'male') {
        borderColor = const Color(0xFF2563EB); // Blue
        cushionFillColor = Colors.white;
        armrestFillColor = const Color(0xFFBFDBFE);
        bottomBarColor = const Color(0xFF2563EB);
        bottomSegmentFillColor = const Color(0xFFBFDBFE);
        textColor = const Color(0xFF1D4ED8);
        genderIcon = Icons.man_rounded;
      } else if (g == 'female') {
        borderColor = const Color(0xFFE11D48); // Pink
        cushionFillColor = Colors.white;
        armrestFillColor = const Color(0xFFFECDD3);
        bottomBarColor = const Color(0xFFE11D48);
        bottomSegmentFillColor = const Color(0xFFFECDD3);
        textColor = const Color(0xFFBE123C);
        genderIcon = Icons.woman_rounded;
      } else {
        // Purple theme from the user's mockup image
        borderColor = const Color(0xFF8B5CF6); // Violet/Purple
        cushionFillColor = Colors.white;
        armrestFillColor = const Color(0xFFDDD6FE); // Light purple fill
        bottomBarColor = const Color(0xFF8B5CF6);
        bottomSegmentFillColor = const Color(0xFFDDD6FE);
        textColor = const Color(0xFF6D28D9);
      }
    } else {
      // Available
      borderColor = const Color(0xFF71717A); // Slate/zinc border
      cushionFillColor = Colors.white;
      armrestFillColor = Colors.white;
      bottomBarColor = const Color(0xFF71717A);
      bottomSegmentFillColor = Colors.white;
      textColor = const Color(0xFF18181B);
    }

    final double armrestWidth = (widget.width * 0.12).clamp(4.0, 8.0);
    final double gap = 1.0;
    final double topOffset = widget.height * 0.15;

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
                  // Left Armrest
                  Positioned(
                    left: 0,
                    top: topOffset,
                    bottom: 0,
                    width: armrestWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: armrestFillColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomLeft: Radius.circular(4),
                        ),
                        border: Border.all(
                          color: borderColor,
                          width: widget.isSelected ? 1.5 : 1.2,
                        ),
                      ),
                    ),
                  ),
                  // Center Cushion / Backrest
                  Positioned(
                    left: armrestWidth + gap,
                    right: armrestWidth + gap,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cushionFillColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                        border: Border.all(
                          color: borderColor,
                          width: widget.isSelected ? 1.5 : 1.2,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Bottom Line and Fill Segment
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: widget.height * 0.18,
                            child: Container(
                              decoration: BoxDecoration(
                                color: bottomSegmentFillColor,
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(3),
                                  bottomRight: Radius.circular(3),
                                ),
                                border: Border(
                                  top: BorderSide(
                                    color: bottomBarColor,
                                    width: widget.isSelected ? 1.5 : 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Seat Label (adjusted to avoid overlapping the bottom bar)
                          Center(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: widget.height * 0.12),
                              child: Text(
                                widget.label,
                                style: TextStyle(
                                  fontSize: (widget.height * 0.28).clamp(9.0, 13.0),
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Right Armrest
                  Positioned(
                    right: 0,
                    top: topOffset,
                    bottom: 0,
                    width: armrestWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: armrestFillColor,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                        border: Border.all(
                          color: borderColor,
                          width: widget.isSelected ? 1.5 : 1.2,
                        ),
                      ),
                    ),
                  ),
                  // Gender Badge Icon
                  if (genderIcon != null)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: borderColor,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 2,
                            )
                          ],
                        ),
                        child: Icon(
                          genderIcon,
                          size: 10,
                          color: Colors.white,
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
