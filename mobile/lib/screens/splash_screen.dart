import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:seaty/widgets/seaty_bus_loading.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/screens/auth_screen.dart';

/// The logo drawn by BOTH the native launch screen and this widget.
const String _kSplashLogoAsset = 'assets/images/app_logo.png';

/// Logical size (points on iOS, dp on Android) of the splash logo.
///
/// This MUST stay in sync with the generated native launch images. iOS draws
/// `LaunchImage` with `contentMode="center"`, i.e. at its natural point size
/// (pixels / scale), and Android draws `@drawable/splash` with
/// `android:gravity="center"`, i.e. at its natural dp size. If the two sizes
/// disagree, the native layer cross-fades into a different-sized logo and you
/// see a second, smaller icon ghosting behind this screen:
///
///   ios/Runner/Assets.xcassets/LaunchImage.imageset/  170 / 340 / 510 px
///   android/.../res/drawable-{m,h,x,xx,xxx}hdpi/splash.png
///                                       170 / 255 / 340 / 510 / 680 px
///
/// Re-running `dart run flutter_native_splash:create` regenerates those at the
/// package's own ratios (125pt) and brings the ghost back — resize them again
/// if you ever do.
const double _kLogoSize = 170.0;

/// Gap between the logo's box and the tagline.
const double _kTaglineGap = 16.0;

// =====================================================================
// DART-LEVEL SPLASH SCREEN (Shows on every Hot Restart)
// =====================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// False until the native splash has been torn down. Everything other than
  /// the logo stays out of the tree until then, so the first frame Flutter
  /// sends to the engine is exactly what the native layer is already showing.
  bool _revealed = false;

  bool _handOffStarted = false;

  @override
  void initState() {
    super.initState();

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handOffStarted) return;
    _handOffStarted = true;
    unawaited(_handOffFromNativeSplash());
  }

  /// Hands control from the native launch screen to this widget.
  ///
  /// `main()` calls `FlutterNativeSplash.preserve()`, which defers the first
  /// frame. Releasing it before the logo is decoded means Flutter's first frame
  /// is blank white, so the native logo fades out onto nothing and the Dart
  /// logo pops in a frame or two later. Waiting for the image cache first makes
  /// the hand-off a fade between two identical pictures.
  Future<void> _handOffFromNativeSplash() async {
    try {
      await precacheImage(const AssetImage(_kSplashLogoAsset), context)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // A missing or slow asset must never leave the app stuck behind the
      // native splash — fall through and hand over regardless.
    }
    FlutterNativeSplash.remove();
    if (mounted) setState(() => _revealed = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The native launch screen centres the logo on the *screen*, not on
          // the safe area. Deliberately no SafeArea here: the notch and home
          // indicator are asymmetric, so insetting would shift the logo up and
          // make it jump on hand-off.
          final logoTop = (constraints.maxHeight - _kLogoSize) / 2;

          return Stack(
            children: [
              Positioned(
                top: logoTop,
                left: 0,
                right: 0,
                height: _kLogoSize,
                child: Image.asset(
                  _kSplashLogoAsset,
                  height: _kLogoSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.directions_bus_rounded,
                    size: 90,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
              // Positioned relative to the logo rather than stacked with it in
              // a Column, so nothing added here can push the logo off centre.
              if (_revealed)
                Positioned(
                  top: logoTop + _kLogoSize + _kTaglineGap,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                          .slideY(
                            begin: 0.2,
                            end: 0,
                            delay: 300.ms,
                            duration: 500.ms,
                          ),
                      const SizedBox(height: 24),
                      const SeatyBusLoadingIndicator.small()
                          .animate()
                          .fadeIn(delay: 500.ms),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
