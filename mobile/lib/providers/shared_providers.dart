import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:seaty/utils/crash_reporting.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:seaty/utils/safe_text.dart';

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

const String _defaultApiBaseUrl = 'https://api.seaty.hashnate.com/api/v1';

/// Sends a diagnostic line to the backend.
///
/// `debugPrint` is a no-op in release builds, so a failure during startup has
/// no other way to reach us. A dead Firebase went unnoticed in production for
/// weeks precisely because its exception was only ever debugPrinted.
Future<void> reportDiagnostic(String message) async {
  debugPrint(message);
  try {
    final prefs = await SharedPreferences.getInstance();
    final base = prefs.getString('apiBaseUrl') ?? _defaultApiBaseUrl;
    await http.post(
      Uri.parse('$base/public/log'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'message': message}),
    );
  } catch (_) {
    // Diagnostics must never break the app.
  }
}

/// Posts an FCM registration token to the backend for the signed-in user.
///
/// One implementation for every caller. This existed as three near-identical
/// copies - here, in `auth_provider` and in `notifications_provider` - and they
/// drifted, which is how the permission request came to be added to two of
/// them and not the third.
Future<bool> postFcmToken(
  String token, {
  String? authToken,
  String? apiBaseUrl,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final auth = authToken ?? prefs.getString('token') ?? '';
    if (auth.isEmpty || auth.startsWith('simulated')) return false;

    final base = apiBaseUrl ?? prefs.getString('apiBaseUrl') ?? _defaultApiBaseUrl;
    final res = await http.post(
      Uri.parse('$base/notifications/fcm-token'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $auth',
      },
      body: json.encode({'fcm_token': token}),
    );
    debugPrint('FCM token registered [${res.statusCode}]: ${shortId(token, 20)}...');
    return res.statusCode == 200;
  } catch (e) {
    debugPrint('Error posting FCM token: $e');
    return false;
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

/// Waits for iOS to hand the app an APNs device token.
///
/// FCM cannot mint a registration token on iOS until this exists. Asking
/// anyway yields null - and the old code went on to call `getToken()`
/// regardless, which is how tokens APNs can never deliver to reached the
/// database, making every send log "sent successfully" while nothing arrived.
Future<String?> _waitForApnsToken({int attempts = 10}) async {
  for (int i = 0; i < attempts; i++) {
    try {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      if (token != null && token.isNotEmpty) return token;
    } catch (e) {
      debugPrint('getAPNSToken failed on attempt ${i + 1}: $e');
    }
    await Future.delayed(const Duration(seconds: 1));
  }
  return null;
}

Future<bool>? _pendingPermissionRequest;

/// Requests notification authorisation and reports the outcome.
///
/// Deliberately separate from [setupPushNotifications]: authorisation is the
/// one step whose absence is invisible, because iOS hands a perfectly valid
/// FCM token to an unauthorised app and then silently discards every push sent
/// to it. Anything that registers a token must gate on this first.
///
/// Concurrent callers share one request so the user sees a single prompt.
Future<bool> ensureNotificationPermission() {
  final pending = _pendingPermissionRequest;
  if (pending != null) return pending;
  final request = _requestNotificationPermission();
  _pendingPermissionRequest = request;
  return request.whenComplete(() => _pendingPermissionRequest = null);
}

Future<bool> _requestNotificationPermission() async {
  if (!firebaseAvailable) return false;
  try {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    final status = settings.authorizationStatus;
    debugPrint('Notification authorization status: $status');
    final granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    if (!granted) {
      await reportDiagnostic('[fcm-permission] not granted: $status');
    }
    return granted;
  } catch (e) {
    await reportDiagnostic('[fcm-permission-error] $e');
    return false;
  }
}

/// Obtains the FCM token and registers it with the backend.
///
/// Returns true once the backend has accepted a token. Refuses to register one
/// the device cannot actually receive on: a token stored for an unauthorised
/// device is worse than no token at all, because FCM accepts every send
/// against it and the backend logs "sent successfully" while the OS drops each
/// message. "No token" at least reads as "cannot deliver".
Future<bool> registerFcmToken({
  required String authToken,
  required String apiBaseUrl,
  int attempts = 5,
}) async {
  if (authToken.isEmpty || authToken.startsWith('simulated')) return false;

  if (!await firebaseReady) {
    // initFirebaseMessaging has already reported why. Without Firebase there
    // is nothing to register and retrying here cannot help.
    return false;
  }

  if (!await ensureNotificationPermission()) return false;

  for (int attempt = 1; attempt <= attempts; attempt++) {
    try {
      if (!kIsWeb && Platform.isIOS && await _waitForApnsToken() == null) {
        await reportDiagnostic(
            '[fcm-apns] no APNs token on attempt $attempt; not registering');
      } else {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          if (await postFcmToken(token,
              authToken: authToken, apiBaseUrl: apiBaseUrl)) {
            return true;
          }
        } else {
          await reportDiagnostic('[fcm-token] null/empty on attempt $attempt');
        }
      }
    } catch (e) {
      await reportDiagnostic('[fcm-register-error] attempt $attempt: $e');
    }
    if (attempt < attempts) {
      await Future.delayed(Duration(seconds: 2 * attempt));
    }
  }
  return false;
}

Future<void> setupPushNotifications() async {
  if (!firebaseAvailable) return;
  final messaging = FirebaseMessaging.instance;

  // Asked for at startup rather than only when a token is wanted, so a user
  // who is not signed in yet still gets the prompt on first launch.
  await ensureNotificationPermission();

  try {
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  } catch (e) {
    debugPrint('setForegroundNotificationPresentationOptions failed: $e');
  }

  // A token rotates on reinstall, restore or a new device. Until this fires
  // the backend's copy is stale and every push to it is silently discarded.
  messaging.onTokenRefresh.listen((newToken) {
    debugPrint('FCM Token refreshed: ${shortId(newToken, 20)}...');
    unawaited(postFcmToken(newToken));
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

  unawaited(messaging.getInitialMessage().then((RemoteMessage? message) {
    if (message != null) {
      debugPrint('Notification clicked (App opened from terminated state): ${message.data}');
    }
  }));
}

final Completer<bool> _firebaseInitCompleter = Completer<bool>();

/// Completes with true once Firebase is up, false if it could not be started.
///
/// It never reports success for a failed initialisation. The previous version
/// completed from a `finally`, so every caller was told "ready" and then walked
/// straight into `[core/no-app]` - silently, because the only record of the
/// real exception was a release-mode `debugPrint`.
Future<bool> get firebaseReady => _firebaseInitCompleter.future;

/// Ground truth for code that cannot await.
bool get firebaseAvailable => Firebase.apps.isNotEmpty;

/// Idempotent - repeat calls return rather than initialising Firebase (and a
/// second background engine) again.
Future<void> initFirebaseMessaging() async {
  if (_firebaseInitCompleter.isCompleted) return;
  final ok = await _initFirebaseMessaging();
  if (!_firebaseInitCompleter.isCompleted) {
    _firebaseInitCompleter.complete(ok);
  }
}

Future<bool> _initFirebaseMessaging() async {
  // Only Android, iOS, web and macOS have native FCM.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    debugPrint('Firebase messaging safely skipped on desktop platform: '
        '${Platform.operatingSystem}');
    return false;
  }

  // Retried because initialisation can lose the race with native plugin
  // registration on a cold start - `PlatformException(channel-error)` means the
  // firebase_core channel has no handler yet, not that Firebase is unusable. A
  // single failure used to disable push for the entire install because nothing
  // ever tried again. The window spans ~6.75s: the channel was observed coming
  // up around 4s on iOS.
  const List<int> backoffMs = <int>[250, 500, 1000, 2000, 3000];
  Object? lastError;
  for (int attempt = 0; attempt <= backoffMs.length; attempt++) {
    try {
      await Firebase.initializeApp();
      lastError = null;
      break;
    } catch (e) {
      lastError = e;
      debugPrint('Firebase.initializeApp failed '
          '(attempt ${attempt + 1}/${backoffMs.length + 1}): $e');
      if (attempt < backoffMs.length) {
        await Future.delayed(Duration(milliseconds: backoffMs[attempt]));
      }
    }
  }

  if (lastError != null || !firebaseAvailable) {
    // Every push path is dead from here. Say so somewhere readable.
    await reportDiagnostic('[firebase-init-failed] '
        '${lastError ?? 'no default app after initializeApp()'}');
    return false;
  }

  try {
    await CrashReporting.enableCrashReporting();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    await reportDiagnostic('[firebase-post-init-error] $e');
  }

  unawaited(setupPushNotifications());
  return true;
}
