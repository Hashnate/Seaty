import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Helper to build clean WebSocket URLs converting https -> wss and stripping invalid :0 ports
String buildWebSocketUrl(String baseUrl, String subPath) {
  try {
    final uri = Uri.parse(baseUrl);
    final isSecure = uri.scheme == 'https' || uri.scheme == 'wss';
    final scheme = isSecure ? 'wss' : 'ws';
    final host = uri.host.isNotEmpty ? uri.host : 'api.seaty.hashnate.com';
    final portPart = (uri.hasPort && uri.port != 80 && uri.port != 443 && uri.port != 0) ? ':${uri.port}' : '';
    
    String basePath = uri.path;
    if (basePath.endsWith('/ws')) {
      basePath = basePath.substring(0, basePath.length - 3);
    }
    if (basePath.endsWith('/')) {
      basePath = basePath.substring(0, basePath.length - 1);
    }

    final cleanSub = subPath.startsWith('/') ? subPath : '/$subPath';
    return '$scheme://$host$portPart$basePath$cleanSub';
  } catch (e) {
    debugPrint('Error building WebSocket URL: $e');
    return '$baseUrl/$subPath';
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint("Handling a background message: ${message.messageId}");
  } catch (e) {
    debugPrint("Background message handler init error: $e");
  }
}

void setupPushNotifications() async {
  try {
    if (Firebase.apps.isEmpty) return;
    final messaging = FirebaseMessaging.instance;

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

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    try {
      final token = await messaging.getToken();
      debugPrint('FCM Token: $token');
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }

    messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM Token refreshed: $newToken');
    });

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

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification clicked (App opened from background): ${message.data}');
    });

    messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('Notification clicked (App opened from terminated state): ${message.data}');
      }
    });
  } catch (e) {
    debugPrint('Push notifications setup skipped: $e');
  }
}

Future<void> initFirebaseMessaging() async {
  try {
    // Only initialize FCM on platforms that support it natively (Android, iOS, Web, macOS)
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux)) {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      setupPushNotifications();
    } else {
      debugPrint('Firebase messaging safely skipped on desktop platform: ${Platform.operatingSystem}');
    }
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }
}

