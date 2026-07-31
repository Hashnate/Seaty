import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:seaty/widgets/seaty_notifications.dart';

late final SharedPreferences globalPrefs;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => globalPrefs);

class SettingsState {
  final String apiBaseUrl;
  final String wsBaseUrl;

  SettingsState({required this.apiBaseUrl, required this.wsBaseUrl});
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final api = prefs.getString('apiBaseUrl') ?? 'https://api.seaty.hashnate.com/api/v1';
    final ws = prefs.getString('wsBaseUrl') ?? 'wss://api.seaty.hashnate.com/api/v1/ws';
    return SettingsState(apiBaseUrl: api, wsBaseUrl: ws);
  }

  void updateServerIp(String ip) {
    final api = 'http://$ip:8000/api/v1';
    final ws = 'ws://$ip:8000/api/v1/ws';
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString('apiBaseUrl', api);
    prefs.setString('wsBaseUrl', ws);
    state = SettingsState(apiBaseUrl: api, wsBaseUrl: ws);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() => SettingsNotifier());

String normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 9) {
    return digits.substring(digits.length - 9);
  }
  return digits;
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

void setupPushNotifications() async {
  final messaging = FirebaseMessaging.instance;

  // Request permission for iOS/Android 13+
  final settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  debugPrint('User granted permission: ${settings.authorizationStatus}');

  // Get FCM token
  try {
    final token = await messaging.getToken();
    debugPrint('FCM Token: $token');
  } catch (e) {
    debugPrint('Error getting FCM token: $e');
  }

  // Listen to foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Got a message whilst in the foreground!');
    if (message.notification != null) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        SeatyNotifications.show(
          context,
          message.notification!.body ??
              message.notification!.title ??
              'New Notification',
          isWarning: false,
        );
      }
    }
  });
}

Future<void> initFirebaseMessaging() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    setupPushNotifications();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
}

