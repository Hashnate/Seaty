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

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final isAuthenticated = prefs.getBool('isAuthenticated') ?? false;
    final role = prefs.getString('role') ?? 'passenger';
    final userName = prefs.getString('userName') ?? 'Guest User';
    final token = prefs.getString('token') ?? '';
    final userNic = prefs.getString('userNic') ?? '';
    final userGender = prefs.getString('userGender') ?? '';
    final userPhone = prefs.getString('userPhone') ?? '';

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

  void _saveSession(AuthState newState) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setBool('isAuthenticated', newState.isAuthenticated);
    prefs.setString('role', newState.role);
    prefs.setString('userName', newState.userName);
    prefs.setString('token', newState.token);
    prefs.setString('userNic', newState.userNic);
    prefs.setString('userGender', newState.userGender);
    prefs.setString('userPhone', newState.userPhone);
  }

  void setRole(String newRole) {
    final newState = state.copyWith(role: newRole);
    state = newState;
    _saveSession(newState);
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
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': data['success'] == true,
          'otp_code': data['otp_code'],
          'message': data['message'],
        };
      }
    } catch (e) {
      debugPrint('Send OTP API error: $e');
    }
    return {'success': false, 'otp_code': null, 'message': 'Network error sending OTP'};
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

  Future<bool> registerPhoneDB(String name, String phone, String role, {String? otpCode}) async {
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
              'otp_code': ?otpCode,
            }),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('API Registration Error: $e');
      return true;
    }
  }

  Future<void> login(String name, String roleSelected, String phoneNumber) async {
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
            }),
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        token = data['access_token'] ?? '';
        if (data['role'] != null && data['role'].toString().isNotEmpty) {
          finalRole = data['role'].toString();
        }
      }
    } catch (e) {
      debugPrint('API Login error: $e.');
      rethrow;
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
    _saveSession(newState);

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
        _saveSession(newState);
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
    _saveSession(localState);

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
        _saveSession(serverState);
        return true;
      } else if (response.statusCode == 401) {
        logout();
      }
    } catch (e) {
      debugPrint('Error updating profile: $e');
    }
    return false;
  }

  void logout() {
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
    _saveSession(newState);
    clearSessionScopedCaches();
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
