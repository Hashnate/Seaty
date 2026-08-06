import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/screens/splash_screen.dart';


// Re-exports for backward compatibility with conductor/owner modules
export 'package:seaty/providers/shared_providers.dart';
export 'package:seaty/providers/auth_provider.dart';
export 'package:seaty/providers/trips_provider.dart';
export 'package:seaty/providers/bookings_provider.dart';
export 'package:seaty/providers/fleet_provider.dart';
export 'package:seaty/providers/gps_tracking_provider.dart';
export 'package:seaty/providers/notifications_provider.dart';
export 'package:seaty/providers/favourites_provider.dart';
export 'package:seaty/widgets/seaty_notifications.dart';
export 'package:seaty/screens/splash_screen.dart';
export 'package:seaty/screens/auth_screen.dart';
export 'package:seaty/screens/passenger_main_screen.dart';
export 'package:seaty/screens/seat_selector_screen.dart';
export 'package:seaty/screens/conductor/conductor_trip_details_screen.dart';
export 'package:seaty/screens/sandbox_payment_screen.dart';
export 'package:seaty/screens/notifications_screen.dart';

// =====================================================================
// APP ENTRYPOINT
// =====================================================================
void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Providers read globalPrefs synchronously, so this one genuinely has to
  // finish before the first build.
  globalPrefs = await SharedPreferences.getInstance();

  runApp(const ProviderScope(child: SeatyApp()));

  // Deliberately started after runApp and never awaited. Firebase.initializeApp()
  // plus the background-handler registration — which boots a second, headless
  // FlutterEngine and registers every plugin into it — used to run before the
  // first frame existed, delaying every cold start. Nothing the splash paints
  // needs Firebase; callers that do await `firebaseReady`.
  unawaited(initFirebaseMessaging());
}

class SeatyApp extends StatelessWidget {
  const SeatyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seaty',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
