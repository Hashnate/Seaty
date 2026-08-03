import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  WidgetsFlutterBinding.ensureInitialized();
  globalPrefs = await SharedPreferences.getInstance();
  await initFirebaseMessaging();
  runApp(const ProviderScope(child: SeatyApp()));
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
