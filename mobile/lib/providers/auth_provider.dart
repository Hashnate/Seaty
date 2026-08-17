import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/providers/active_trips_provider.dart';
import 'package:seaty/providers/bookings_provider.dart';
import 'package:seaty/providers/favourites_provider.dart';
import 'package:seaty/providers/fleet_provider.dart';
import 'package:seaty/providers/gps_tracking_provider.dart';
import 'package:seaty/providers/notifications_provider.dart';
import 'package:seaty/providers/trips_provider.dart';
import 'package:seaty/utils/safe_text.dart';

/// A sign-in failure with a message already fit to show the user — typically
/// the backend's `detail` for a wrong, expired, or rate-limited OTP.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthState {
  final bool isAuthenticated;
  final String role;
  final String userName;
  final String token;
  final String userNic;
  final String userGender;
  final String userPhone;

  AuthState({
    required this.isAuthenticated,
    required this.role,
    required this.userName,
    required this.token,
    required this.userNic,
    required this.userGender,
    required this.userPhone,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? role,
    String? userName,
    String? token,
    String? userNic,
    String? userGender,
    String? userPhone,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      role: role ?? this.role,
      userName: userName ?? this.userName,
      token: token ?? this.token,
      userNic: userNic ?? this.userNic,
      userGender: userGender ?? this.userGender,
      userPhone: userPhone ?? this.userPhone,
    );
  }
}

/// Session keys in SharedPreferences. Listed so logout can remove every one -
/// leaving any behind is what let a stale flag resurrect a signed-out session.
const _kSessionKeys = <String>[
  'isAuthenticated', 'role', 'userName', 'token', 'userNic', 'userGender', 'userPhone',
];

/// Whether a stored token could still authenticate a request.
///
/// The restored session is only as trustworthy as the token in it, so this is
/// what decides whether the app is signed in — not a separate boolean that can
/// disagree with it. Also catches an expired token (they last 7 days), which
/// would otherwise show the home screen and then 401 on everything.
bool _tokenIsUsable(String token) {
  if (token.isEmpty || token.startsWith('simulated')) return false;
  try {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight(payload.length + ((4 - payload.length % 4) % 4), '=');
    final claims = json.decode(utf8.decode(base64.decode(payload)));
    final exp = claims is Map ? claims['exp'] : null;
    if (exp is! int) return false;
    return DateTime.now().millisecondsSinceEpoch < exp * 1000;
  } catch (_) {
    // Anything unparseable is not something we should trust.
    return false;
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final role = prefs.getString('role') ?? 'passenger';
    final userName = prefs.getString('userName') ?? 'Guest User';
    final token = prefs.getString('token') ?? '';
    final userNic = prefs.getString('userNic') ?? '';
    final userGender = prefs.getString('userGender') ?? '';
    final userPhone = prefs.getString('userPhone') ?? '';

    // Both must hold. The flag alone was enough to restore a session, so a
    // logout whose write never reached disk - force-closing the app before
    // SharedPreferences flushed - came back signed in on next launch.
    final isAuthenticated =
        (prefs.getBool('isAuthenticated') ?? false) && _tokenIsUsable(token);

    final authState = AuthState(
      isAuthenticated: isAuthenticated,
      role: role,
      userName: userName,
      token: token,
      userNic: userNic,
      userGender: userGender,
      userPhone: userPhone,
    );

    if (isAuthenticated && token.isNotEmpty && !token.startsWith('simulated')) {
      Future.microtask(() => loadProfile());
    }

    return authState;
  }

  /// Persists the session. Awaited, unlike before: `setString` and friends
  /// update SharedPreferences' in-memory cache immediately but reach the
  /// platform asynchronously, so an unawaited write is lost if the process
  /// dies first. That is invisible for a sign-in (the app keeps running) and
  /// exactly the bug for a sign-out.
  Future<void> _saveSession(AuthState newState) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await Future.wait([
      prefs.setBool('isAuthenticated', newState.isAuthenticated),
      prefs.setString('role', newState.role),
      prefs.setString('userName', newState.userName),
      prefs.setString('token', newState.token),
      prefs.setString('userNic', newState.userNic),
      prefs.setString('userGender', newState.userGender),
      prefs.setString('userPhone', newState.userPhone),
    ]);
  }

  Future<void> setRole(String newRole) async {
    final newState = state.copyWith(role: newRole);
    state = newState;
    await _saveSession(newState);
  }

  Future<Map<String, dynamic>> checkPhoneDB(
    String phone, {
    String? preferredRole,
  }) async {
    final settings = ref.read(settingsProvider);
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final normPhone = normalizePhone(phone);
    if (normPhone.isEmpty) {
      return {'exists': false, 'name': 'Guest User', 'role': 'passenger'};
    }

    final String roleHint = preferredRole ?? 'passenger';
    try {
      final response = await http
          .post(
            Uri.parse('${settings.apiBaseUrl}/auth/phone/check'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'phone_number': cleanPhone,
              'role': roleHint,
            }),
          )
          .timeout(const Duration(seconds: 5));

      debugPrint('VPS check response [${response.statusCode}]: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['exists'] == true) {
          final String name =
              (data['name'] ?? data['full_name'] ?? 'User').toString();
          final String? serverRole = data['role']?.toString();
          final String finalRole = (serverRole != null && serverRole.isNotEmpty)
              ? serverRole
              : roleHint;
          debugPrint(
            'VPS DB Found: $cleanPhone -> $name | serverRole=$serverRole | preferredRole=$preferredRole | finalRole=$finalRole',
          );
          return {'exists': true, 'name': name, 'role': finalRole};
        }
      }
    } catch (e) {
      debugPrint('VPS API check error: $e');
    }

    return {
      'exists': false,
      'name': 'Guest User',
      'role': preferredRole ?? 'passenger',
    };
  }

  Future<Map<String, dynamic>> sendOtp(String phone) async {
    final settings = ref.read(settingsProvider);
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    try {
      final response = await http
          .post(
            Uri.parse('${settings.apiBaseUrl}/auth/otp/send'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'phone_number': cleanPhone}),
          )
          .timeout(const Duration(seconds: 10));

      final dynamic data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': data['success'] == true,
          'otp_code': data['otp_code'],
          'message': data['message'],
        };
      } else {
        String message = 'Failed to send OTP.';
        if (data is Map && data['detail'] != null) {
          message = data['detail'] is String ? data['detail'] : json.encode(data['detail']);
        }
        return {'success': false, 'otp_code': null, 'message': message};
      }
    } catch (e) {
      debugPrint('Send OTP API error: $e');
    }
    return {'success': false, 'otp_code': null, 'message': 'Network error sending OTP. Please check your internet connection.'};
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String otpCode) async {
    final settings = ref.read(settingsProvider);
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    try {
      final response = await http
          .post(
            Uri.parse('${settings.apiBaseUrl}/auth/otp/verify'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'phone_number': cleanPhone,
              'otp_code': otpCode,
            }),
          )
          .timeout(const Duration(seconds: 5));

      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'OTP Verified'};
      } else {
        return {'success': false, 'message': data['detail'] ?? 'Invalid OTP code'};
      }
    } catch (e) {
      debugPrint('Verify OTP API error: $e');
      return {'success': false, 'message': 'Network error verifying OTP'};
    }
  }

  /// Creates a passenger account. [otpCode] is required — the backend verifies
  /// it before creating anything, so a caller without one cannot register.
  Future<bool> registerPhoneDB(String name, String phone, String role, {required String otpCode}) async {
    final settings = ref.read(settingsProvider);
    final assignedRole = role.isNotEmpty ? role : 'passenger';
    try {
      final response = await http
          .post(
            Uri.parse('${settings.apiBaseUrl}/auth/phone/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'phone_number': phone,
              'full_name': name,
              'role': assignedRole,
              'otp_code': otpCode,
            }),
          )
          .timeout(const Duration(seconds: 15));

      return response.statusCode == 201;
    } catch (e) {
      // Was `return true`: a timeout or dropped connection was reported to the
      // caller as a successful registration, so sign-up appeared to work and
      // the following sign-in then failed for no visible reason.
      debugPrint('API Registration Error: $e');
      return false;
    }
  }

  /// Signs in with phone + OTP.
  ///
  /// [otpCode] is mandatory: the backend verifies it here and consumes it, so a
  /// prior `/auth/otp/verify` call is a UX nicety, not the security check.
  Future<void> login(
    String name,
    String roleSelected,
    String phoneNumber, {
    required String otpCode,
  }) async {
    final settings = ref.read(settingsProvider);
    String token = '';
    String finalRole = roleSelected;

    try {
      final response = await http
          .post(
            Uri.parse('${settings.apiBaseUrl}/auth/phone/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'phone_number': phoneNumber,
              'role': roleSelected,
              'otp_code': otpCode,
            }),
          )
          // 2s was too tight for a mobile network, and a timeout here now costs
          // the user their one-shot code.
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        // Previously any non-200 fell through and the session was still marked
        // authenticated with an empty token, leaving the app "signed in" but
        // 401ing on every request. Now that a wrong or expired OTP is a normal
        // outcome, that has to surface.
        String detail = 'Sign-in failed. Please try again.';
        try {
          final body = json.decode(response.body);
          if (body is Map && body['detail'] is String) detail = body['detail'];
        } catch (_) {}
        throw AuthException(detail);
      }

      final data = json.decode(response.body);
      token = data['access_token'] ?? '';
      if (data['role'] != null && data['role'].toString().isNotEmpty) {
        finalRole = data['role'].toString();
      }
      if (token.isEmpty) {
        throw AuthException('Sign-in failed. Please try again.');
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('API Login error: $e.');
      throw AuthException('Could not reach Seaty. Check your connection and try again.');
    }

    final newState = AuthState(
      isAuthenticated: true,
      role: finalRole,
      userName: name,
      token: token,
      userNic: state.userNic,
      userGender: state.userGender,
      userPhone: phoneNumber,
    );

    state = newState;
    await _saveSession(newState);

    // Load profile immediately to populate gender, NIC etc.
    loadProfile();
  }

  Future<void> syncFcmToken() async {
    if (state.token.isEmpty || state.token.startsWith('simulated')) return;
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
            if (apnsToken != null) break;
            await Future.delayed(const Duration(seconds: 1));
          }
          if (apnsToken == null) {
            debugPrint('syncFcmToken: APNs token still null on attempt ${attempt + 1}, attempting getToken fallback');
          }
        }

        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          final res = await http.post(
            Uri.parse('${settings.apiBaseUrl}/notifications/fcm-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${state.token}',
            },
            body: json.encode({'fcm_token': fcmToken}),
          );
          debugPrint('FCM Token synced from AuthProvider [${res.statusCode}]: ${shortId(fcmToken, 20)}...');
          if (res.statusCode == 200) break;
        } else {
          debugPrint('FCM token is null/empty on syncFcmToken attempt ${attempt + 1}');
        }
      } catch (e) {
        debugPrint('FCM token sync attempt ${attempt + 1} failed: $e');
      }
      await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
  }

  Future<void> loadProfile() async {
    if (state.token.isEmpty || state.token.startsWith('simulated')) return;
    syncFcmToken();
    final settings = ref.read(settingsProvider);
    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/auth/me'),
            headers: {'Authorization': 'Bearer ${state.token}'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newState = state.copyWith(
          userName: data['full_name'] ?? state.userName,
          userPhone: data['phone_number'] ?? state.userPhone,
          userNic: data['nic_number'] ?? '',
          userGender: data['gender'] ?? '',
          role: (data['role'] != null && data['role'].toString().isNotEmpty)
              ? data['role'].toString()
              : state.role,
        );
        state = newState;
        await _saveSession(newState);
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<bool> updateProfile(
    String name,
    String nic,
    String gender,
    String phone,
  ) async {
    final settings = ref.read(settingsProvider);
    final localState = state.copyWith(
      userName: name,
      userNic: nic,
      userGender: gender,
      userPhone: phone,
    );
    state = localState;
    await _saveSession(localState);

    if (state.token.isEmpty || state.token.startsWith('simulated')) return true;

    try {
      final response = await http
          .put(
            Uri.parse('${settings.apiBaseUrl}/auth/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${state.token}',
            },
            body: json.encode({
              'full_name': name,
              'nic_number': nic,
              'gender': gender,
              'phone_number': phone,
            }),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverState = state.copyWith(
          userName: data['full_name'] ?? state.userName,
          userNic: data['nic_number'] ?? state.userNic,
          userGender: data['gender'] ?? state.userGender,
          userPhone: data['phone_number'] ?? state.userPhone,
        );
        state = serverState;
        await _saveSession(serverState);
        return true;
      } else if (response.statusCode == 401) {
        await logout();
      }
    } catch (e) {
      debugPrint('Error updating profile: $e');
    }
    return false;
  }

  /// Signs out and waits for it to actually be on disk.
  ///
  /// Await this before letting the user leave the screen. The previous version
  /// returned immediately: the in-memory state flipped so the UI showed the
  /// sign-in screen, but the write to SharedPreferences was still in flight.
  /// Force-closing the app at that point lost it, and the next launch restored
  /// the signed-in session.
  Future<void> logout() async {
    // Kill the token server-side first, while we still hold it. This is what
    // makes sign-out real: even if the local write never reaches disk - an iOS
    // force-close can lose an unflushed UserDefaults write - the token is dead,
    // so the next launch 401s and lands on the sign-in screen anyway.
    //
    // Best-effort: offline, or a backend that has not shipped /auth/logout yet,
    // must not trap the user in a signed-in app. Local state is cleared either
    // way.
    final oldToken = state.token;
    if (oldToken.isNotEmpty && !oldToken.startsWith('simulated')) {
      try {
        final settings = ref.read(settingsProvider);
        await http
            .post(
              Uri.parse('${settings.apiBaseUrl}/auth/logout'),
              headers: {'Authorization': 'Bearer $oldToken'},
            )
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('Server-side logout failed (clearing locally anyway): $e');
      }
    }

    final newState = AuthState(
      isAuthenticated: false,
      role: 'passenger',
      userName: 'Guest User',
      token: '',
      userNic: '',
      userGender: '',
      userPhone: '',
    );
    state = newState;
    clearSessionScopedCaches();

    // Removed rather than overwritten, so a partially applied write cannot
    // leave a key behind that still looks like a session.
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      await Future.wait([for (final k in _kSessionKeys) prefs.remove(k)]);
    } catch (e) {
      debugPrint('Error clearing session: $e');
    }
  }

  /// Drops every provider holding data belonging to the signed-out account.
  ///
  /// These providers live for the lifetime of the app, so without this the next
  /// account to sign in inherits the previous user's trips, bookings and
  /// notifications - a conductor could be shown another company's bus and
  /// passenger manifest. Invalidating also disposes the GPS notifier, closing
  /// its websockets so the old session stops broadcasting.
  void clearSessionScopedCaches() {
    ref.invalidate(tripsProvider);
    ref.invalidate(activeTripsProvider);
    ref.invalidate(bookingsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(favouritesProvider);
    ref.invalidate(fleetProvider);
    ref.invalidate(gpsTrackingProvider);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() => AuthNotifier());
