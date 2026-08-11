import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/providers/auth_provider.dart';
import 'package:seaty/providers/bookings_provider.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:seaty/utils/safe_text.dart';

const Set<String> _kBookingAffectingNotificationTypes = {
  'booking',
  'trip_ongoing',
  'trip_cancelled',
  'trip_rescheduled',
};

class NotificationsState {
  final List<Map<String, dynamic>> notifications;
  final bool isNotiListenerConnected;

  NotificationsState({
    required this.notifications,
    required this.isNotiListenerConnected,
  });

  int get unreadNotificationsCount => notifications
      .where((n) => n['is_read'] == false || n['is_read'] == 0)
      .length;

  NotificationsState copyWith({
    List<Map<String, dynamic>>? notifications,
    bool? isNotiListenerConnected,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      isNotiListenerConnected: isNotiListenerConnected ?? this.isNotiListenerConnected,
    );
  }
}

class NotificationsNotifier extends Notifier<NotificationsState> {
  WebSocketChannel? _notificationsChannel;

  @override
  NotificationsState build() {
    final auth = ref.watch(authProvider);

    ref.onDispose(() {
      _notificationsChannel?.sink.close();
    });

    if (auth.isAuthenticated) {
      Future.microtask(() {
        fetchNotifications();
        startNotificationsListener();
        registerFcmTokenWithBackend();
      });
    } else {
      Future.microtask(() => stopNotificationsListener());
    }

    return NotificationsState(
      notifications: [],
      isNotiListenerConnected: false,
    );
  }

  Future<void> registerFcmTokenWithBackend() async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) return;
    // main() starts Firebase after runApp, so this can be reached first.
    await firebaseReady;
    final settings = ref.read(settingsProvider);

    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        // On iOS, poll briefly for APNs token readiness before requesting FCM token
        if (!kIsWeb && Platform.isIOS) {
          String? apnsToken;
          for (int i = 0; i < 5; i++) {
            apnsToken = await FirebaseMessaging.instance.getAPNSToken();
            if (apnsToken != null) {
              debugPrint('iOS APNs token ready on attempt ${i + 1}');
              break;
            }
            await Future.delayed(const Duration(seconds: 1));
          }
          if (apnsToken == null) {
            debugPrint('FCM registration notice: APNs token still null on attempt ${attempt + 1}, attempting getToken fallback');
          }
        }

        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          final response = await http.post(
            Uri.parse('${settings.apiBaseUrl}/notifications/fcm-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${auth.token}',
            },
            body: json.encode({'fcm_token': fcmToken}),
          );
          debugPrint('FCM token registered with backend [${response.statusCode}]: ${shortId(fcmToken, 20)}...');
          if (response.statusCode == 200) break;
        } else {
          debugPrint('FCM token is null/empty on attempt ${attempt + 1}');
        }
      } catch (e) {
        debugPrint('Error registering FCM token (attempt ${attempt + 1}): $e');
      }
      await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
  }

  Future<void> fetchNotifications() async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) return;
    final settings = ref.read(settingsProvider);

    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/notifications'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${auth.token}',
            },
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        state = state.copyWith(notifications: List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) {
      final List<Map<String, dynamic>> list = [...state.notifications];
      final notiIndex = list.indexWhere((n) => n['id'].toString() == notificationId);
      if (notiIndex != -1) {
        list[notiIndex] = {...list[notiIndex], 'is_read': true};
        state = state.copyWith(notifications: list);
      }
      return;
    }

    final settings = ref.read(settingsProvider);
    try {
      final response = await http.post(
        Uri.parse('${settings.apiBaseUrl}/notifications/$notificationId/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<Map<String, dynamic>> list = [...state.notifications];
        final notiIndex = list.indexWhere((n) => n['id'].toString() == notificationId);
        if (notiIndex != -1) {
          list[notiIndex] = {...list[notiIndex], 'is_read': true};
          state = state.copyWith(notifications: list);
        }
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllNotificationsAsRead() async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) {
      final List<Map<String, dynamic>> list = state.notifications.map((n) {
        return {...n, 'is_read': true};
      }).toList();
      state = state.copyWith(notifications: list);
      return;
    }

    final settings = ref.read(settingsProvider);
    try {
      final response = await http.post(
        Uri.parse('${settings.apiBaseUrl}/notifications/read-all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<Map<String, dynamic>> list = state.notifications.map((n) {
          return {...n, 'is_read': true};
        }).toList();
        state = state.copyWith(notifications: list);
      }
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  void startNotificationsListener() {
    stopNotificationsListener();
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) return;

    state = state.copyWith(isNotiListenerConnected: true);
    final settings = ref.read(settingsProvider);

    try {
      final wsUrl = buildWebSocketUrl(settings.apiBaseUrl, 'notifications/ws?token=${auth.token}');
      _notificationsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _notificationsChannel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message);
            final List<Map<String, dynamic>> list = [data, ...state.notifications];
            state = state.copyWith(notifications: list);

            // Keep the local bookings cache in sync so tapping this
            // notification resolves to the right booking immediately,
            // instead of relying only on the retry-on-tap fallback.
            if (_kBookingAffectingNotificationTypes.contains(data['type'])) {
              ref.read(bookingsProvider.notifier).loadBookings();
            }

            final context = navigatorKey.currentContext;
            if (context != null) {
              SeatyNotifications.show(
                context,
                data['message'] ?? '',
                isError: data['type'] == 'error' || data['type'] == 'failure',
                isWarning: data['type'] == 'warning',
              );
            }
          } catch (e) {
            debugPrint('Error parsing notification message: $e');
          }
        },
        onError: (err) {
          debugPrint('Notification WS connection notice: $err');
          state = state.copyWith(isNotiListenerConnected: false);
        },
        onDone: () {
          state = state.copyWith(isNotiListenerConnected: false);
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Notification WS connection notice: $e');
      state = state.copyWith(isNotiListenerConnected: false);
    }
  }

  void stopNotificationsListener() {
    _notificationsChannel?.sink.close();
    _notificationsChannel = null;
    state = state.copyWith(isNotiListenerConnected: false);
  }
}

final notificationsProvider = NotifierProvider<NotificationsNotifier, NotificationsState>(() => NotificationsNotifier());
