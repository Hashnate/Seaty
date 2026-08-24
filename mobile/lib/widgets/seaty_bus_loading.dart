import 'package:flutter/material.dart';

/// A custom loading indicator showing a side-view bus driving from left to right.
class SeatyBusLoadingIndicator extends StatefulWidget {
  final String? message;
  final double height;
  final Color busColor;
  final bool isSmall;

  const SeatyBusLoadingIndicator({
    super.key,
    this.message,
    this.height = 65,
    this.busColor = const Color(0xFF2563EB),
    this.isSmall = false,
  });

  const SeatyBusLoadingIndicator.small({
    super.key,
    this.message,
    this.height = 32,
    this.busColor = const Color(0xFF2563EB),
  }) : isSmall = true;

  @override
  State<SeatyBusLoadingIndicator> createState() => _SeatyBusLoadingIndicatorState();
}

class _SeatyBusLoadingIndicatorState extends State<SeatyBusLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.isSmall ? 1300 : 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busWidth = widget.isSmall ? 48.0 : 68.0;
    final busHeight = widget.isSmall ? 24.0 : 34.0;

    if (widget.isSmall) {
      return SizedBox(
        height: widget.height,
        width: 140,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final busX = -(busWidth + 10) + (_controller.value * (trackWidth + busWidth + 20));
                    return Positioned(
                      left: busX,
                      child: CustomPaint(
                        size: Size(busWidth, busHeight),
                        painter: _SideViewBusPainter(color: widget.busColor),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: widget.height,
          width: 220,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final busX = -(busWidth + 10) + (_controller.value * (trackWidth + busWidth + 20));
                      return Positioned(
                        left: busX,
                        child: CustomPaint(
                          size: Size(busWidth, busHeight),
                          painter: _SideViewBusPainter(color: widget.busColor),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
        if (widget.message != null && widget.message!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            widget.message!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ],
    );
  }
}

/// CustomPainter rendering the exact Side-View Bus Silhouette reference image in solid Blue.
class _SideViewBusPainter extends CustomPainter {
  final Color color;

  _SideViewBusPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final wheelRadius = h * 0.17;
    final wheelY = h - wheelRadius;
    final rearWheelX = w * 0.22;
    final frontWheelX = w * 0.78;

    // Body Outer Boundary Path with Wheel Arches
    final path = Path();
    
    // Bottom rear start
    path.moveTo(0, h * 0.76);
    // Rear bottom rounded corner
    path.quadraticBezierTo(0, h * 0.85, w * 0.06, h * 0.85);
    
    // Line to rear wheel arch
    path.lineTo(rearWheelX - wheelRadius - 2, h * 0.85);
    // Rear wheel arch cutout
    path.arcToPoint(
      Offset(rearWheelX + wheelRadius + 2, h * 0.85),
      radius: Radius.circular(wheelRadius + 2),
      clockwise: false,
    );
    
    // Line between wheels
    path.lineTo(frontWheelX - wheelRadius - 2, h * 0.85);
    // Front wheel arch cutout
    path.arcToPoint(
      Offset(frontWheelX + wheelRadius + 2, h * 0.85),
      radius: Radius.circular(wheelRadius + 2),
      clockwise: false,
    );
    
    // Line to front bumper bottom right
    path.lineTo(w * 0.94, h * 0.85);
    
    // Front bumper step cutout
    path.lineTo(w * 0.94, h * 0.75);
    path.lineTo(w, h * 0.75);
    
    // Front right wall up to sloped windshield
    path.lineTo(w, h * 0.32);
    
    // Sloped windshield corner up to roof
    path.quadraticBezierTo(w, h * 0.05, w * 0.86, h * 0.05);
    
    // Roof to rear top curve
    path.lineTo(w * 0.14, h * 0.05);
    path.quadraticBezierTo(0, h * 0.05, 0, h * 0.30);
    
    path.close();

    // 1. Draw Main Blue Body
    canvas.drawPath(path, paint);

    // 2. Draw Wheel Rings (Black outer tire ring with white/transparent inner hub)
    final tirePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final innerHubPaint = Paint()
      ..color = (color == Colors.white) ? const Color(0xFF2563EB) : Colors.white
      ..style = PaintingStyle.fill;
    final centerDotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Rear Wheel
    canvas.drawCircle(Offset(rearWheelX, wheelY), wheelRadius + 0.5, tirePaint);
    canvas.drawCircle(Offset(rearWheelX, wheelY), wheelRadius * 0.58, innerHubPaint);
    canvas.drawCircle(Offset(rearWheelX, wheelY), wheelRadius * 0.28, centerDotPaint);

    // Front Wheel
    canvas.drawCircle(Offset(frontWheelX, wheelY), wheelRadius + 0.5, tirePaint);
    canvas.drawCircle(Offset(frontWheelX, wheelY), wheelRadius * 0.58, innerHubPaint);
    canvas.drawCircle(Offset(frontWheelX, wheelY), wheelRadius * 0.28, centerDotPaint);

    // 3. Draw 5 Window Cutouts (White rectangles with vertical dividers)
    final windowTop = h * 0.16;
    final windowBottom = h * 0.52;
    
    final windowPaint = Paint()
      ..color = (color == Colors.white) ? const Color(0xFF2563EB) : Colors.white
      ..style = PaintingStyle.fill;

    final windowAreaStart = w * 0.08;
    final windowAreaEnd = w * 0.90;
    final windowAreaWidth = windowAreaEnd - windowAreaStart;
    
    final winCount = 5;
    final dividerWidth = 2.0;
    final totalDividerWidth = dividerWidth * (winCount - 1);
    final winWidth = (windowAreaWidth - totalDividerWidth) / winCount;

    for (int i = 0; i < winCount; i++) {
      final left = windowAreaStart + i * (winWidth + dividerWidth);
      final right = left + winWidth;
      
      RRect winRect;
      if (i == 0) {
        // Rear-most passenger window (rounded top-left corner)
        winRect = RRect.fromRectAndCorners(
          Rect.fromLTRB(left, windowTop, right, windowBottom),
          topLeft: const Radius.circular(6),
        );
      } else if (i == winCount - 1) {
        // Front windshield window (sloped rounded top-right & bottom-right corner)
        winRect = RRect.fromRectAndCorners(
          Rect.fromLTRB(left, windowTop, right + 1.5, windowBottom),
          topRight: const Radius.circular(8),
          bottomRight: const Radius.circular(5),
        );
      } else {
        // Middle passenger windows
        winRect = RRect.fromRectAndCorners(
          Rect.fromLTRB(left, windowTop, right, windowBottom),
        );
      }
      canvas.drawRRect(winRect, windowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SideViewBusPainter oldDelegate) =>
      oldDelegate.color != color;
}
