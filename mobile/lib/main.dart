import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:video_player/video_player.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:seaty/screens/tracker_screen.dart';
import 'package:seaty/screens/ticket_screen.dart';
import 'package:seaty/screens/profile_screen.dart';
import 'package:seaty/screens/bus_details_screen.dart';
import 'package:seaty/screens/owner/owner_main_screen.dart';
import 'package:seaty/screens/conductor/conductor_main_screen.dart';

// =====================================================================
// 1. STATE MANAGEMENT (PROVIDER)
// =====================================================================
class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;

  String _role = 'passenger'; // 'passenger' | 'owner'
  bool _isAuthenticated = false;
  String _userName = 'Guest User';
  String _token = '';
  String _userNic = '';
  String _userGender = '';
  String _userPhone = '';

  String get token => _token;
  String get userNic => _userNic;
  String get userGender => _userGender;
  String get userPhone => _userPhone;

  // API URL Config
  String apiBaseUrl = 'https://api.seaty.hashnate.com/api/v1';
  String wsBaseUrl = 'wss://api.seaty.hashnate.com/api/v1/ws';

  AppState(this._prefs) {
    _loadSession();
    // Load trips publicly for guest, and all details if authenticated
    loadTrips();
    if (_isAuthenticated) {
      loadVehicles();
      loadConductors();
      loadBookings();
      loadProfile();
      fetchNotifications();
      startNotificationsListener();
    }
  }
  void _loadSession() {
    _isAuthenticated = _prefs.getBool('isAuthenticated') ?? false;
    _role = _prefs.getString('role') ?? 'passenger';
    _userName = _prefs.getString('userName') ?? 'Guest User';
    _token = _prefs.getString('token') ?? '';
    _userNic = _prefs.getString('userNic') ?? '';
    _userGender = _prefs.getString('userGender') ?? '';
    _userPhone = _prefs.getString('userPhone') ?? '';
    apiBaseUrl = 'https://api.seaty.hashnate.com/api/v1';
    wsBaseUrl = 'wss://api.seaty.hashnate.com/api/v1/ws';
    _saveSession();

    final savedConductors = _prefs.getString('conductors_json');
    if (savedConductors != null && savedConductors.isNotEmpty) {
      try {
        final List<dynamic> list = json.decode(savedConductors);
        for (var item in list) {
          if (item is Map<String, dynamic>) {
            final norm = normalizePhone(
              (item['phone_number'] ?? '').toString(),
            );
            if (!_conductorsList.any(
              (c) =>
                  normalizePhone((c['phone_number'] ?? '').toString()) == norm,
            )) {
              _conductorsList.add(item);
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading saved conductors: $e');
      }
    }
  }

  void _saveSession() {
    _prefs.setBool('isAuthenticated', _isAuthenticated);
    _prefs.setString('role', _role);
    _prefs.setString('userName', _userName);
    _prefs.setString('token', _token);
    _prefs.setString('userNic', _userNic);
    _prefs.setString('userPhone', _userPhone);
    _prefs.setString('apiBaseUrl', apiBaseUrl);
    _prefs.setString('wsBaseUrl', wsBaseUrl);
    _saveConductorsToPrefs();
  }

  void _saveConductorsToPrefs() {
    try {
      _prefs.setString('conductors_json', json.encode(_conductorsList));
    } catch (e) {
      debugPrint('Error saving conductors to prefs: $e');
    }
  }

  void updateServerIp(String ip) {
    apiBaseUrl = 'http://$ip:8000/api/v1';
    wsBaseUrl = 'ws://$ip:8000/api/v1/ws';
    notifyListeners();
  }

  // Local state fallbacks (ensures full interactivity offline/local)
  final List<Map<String, dynamic>> _vehicles = [
    {
      'id': 'v-deluxe',
      'name': 'Colombo Express VIP',
      'reg': 'WP-ND-8942',
      'total_seats': 40,
      'is_verified': true,
    },
  ];

  final List<Map<String, dynamic>> _trips = [
    {
      'id': 't1',
      'origin': 'Colombo Fort',
      'destination': 'Galle Multi-modal',
      'departure': '2026-07-13 14:00',
      'price': 1600.0,
      'bus_name': 'Colombo Express VIP',
      'reg': 'WP-ND-8942',
    },
    {
      'id': 't2',
      'origin': 'Colombo Fort',
      'destination': 'Kandy Goods Shed',
      'departure': '2026-07-13 16:30',
      'price': 1800.0,
      'bus_name': 'Kandy Intercity Deluxe',
      'reg': 'CP-NB-7721',
    },
  ];

  final List<Map<String, dynamic>> _bookings = [];

  // Selected seats state
  final List<String> _selectedSeats = [];
  final Map<String, String> _selectedSeatGenders = {};
  List<String> _bookedSeats = [];
  List<String> _heldSeats = [];
  Map<String, String> _seatGenders = {};

  // Tracking bus variables
  Map<String, dynamic>? _trackedBusLocation;
  WebSocketChannel? _trackingChannel;
  Timer? _trackingTimer;
  bool _isTracking = false;

  // Senders variables (Owner streaming GPS)
  WebSocketChannel? _streamingChannel;
  bool _isStreamingGPS = false;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Notifications variables
  WebSocketChannel? _notificationsChannel;
  List<Map<String, dynamic>> _notifications = [];
  bool _isNotiListenerConnected = false;

  // Getters
  String get role => _role;
  bool get isAuthenticated => _isAuthenticated;
  String get userName => _userName;
  List<Map<String, dynamic>> get vehicles => _vehicles;
  List<Map<String, dynamic>> get trips => _trips;
  List<Map<String, dynamic>> get bookings => _bookings;
  List<String> get selectedSeats => _selectedSeats;
  Map<String, String> get selectedSeatGenders => _selectedSeatGenders;
  List<String> get bookedSeats => _bookedSeats;
  List<String> get heldSeats => _heldSeats;
  Map<String, String> get seatGenders => _seatGenders;
  Map<String, dynamic>? get trackedBusLocation => _trackedBusLocation;
  bool get isTracking => _isTracking;
  bool get isStreamingGPS => _isStreamingGPS;
  List<Map<String, dynamic>> get notifications => _notifications;
  int get unreadNotificationsCount => _notifications
      .where((n) => n['is_read'] == false || n['is_read'] == 0)
      .length;

  String normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9) {
      return digits.substring(digits.length - 9);
    }
    return digits;
  }

  Future<Map<String, dynamic>> checkPhoneDB(
    String phone, {
    String? preferredRole,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final normPhone = normalizePhone(phone);
    if (normPhone.isEmpty) {
      return {'exists': false, 'name': 'Guest User', 'role': 'passenger'};
    }

    // The VPS API requires a "role" field in the request body.
    // We send the portal selection as the role hint.
    // The server now returns the user's ACTUAL role from the database,
    // so we always trust the server-returned role over anything else.
    final String roleHint = preferredRole ?? 'passenger';
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/phone/check'),
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
          // Server role is the absolute authority (now returned by the API)
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

    // Phone not found in DB — new user, use the portal they selected
    return {
      'exists': false,
      'name': 'Guest User',
      'role': preferredRole ?? 'passenger',
    };
  }

  Future<bool> registerPhoneDB(String name, String phone, String role) async {
    final assignedRole = role.isNotEmpty ? role : 'passenger';
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/phone/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'phone_number': phone,
              'full_name': name,
              'role': assignedRole,
            }),
          )
          .timeout(const Duration(seconds: 2));

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('API Registration Error: $e');
      return true;
    }
  }

  // Toggle roles
  void setRole(String newRole) {
    _role = newRole;
    notifyListeners();
  }

  // Real Login
  void login(String name, String roleSelected, String phoneNumber) async {
    _userName = name;
    _role = roleSelected;
    _isAuthenticated = true;

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/phone/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'phone_number': phoneNumber,
              'role': roleSelected,
            }),
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['access_token'];
        if (data['role'] != null && data['role'].toString().isNotEmpty) {
          _role = data['role'].toString();
        }
      }
    } catch (e) {
      debugPrint('API Login error: $e.');
      _token = '';
      rethrow;
    }

    _saveSession();
    loadVehicles();
    loadConductors();
    loadTrips();
    loadBookings();
    loadProfile();
    fetchNotifications();
    startNotificationsListener();
    notifyListeners();
  }

  Future<void> fetchNotifications() async {
    if (_token.isEmpty || _token.startsWith('simulated')) return;
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/notifications'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _notifications = List<Map<String, dynamic>>.from(data);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    if (_token.isEmpty || _token.startsWith('simulated')) {
      final notiIndex = _notifications.indexWhere(
        (n) => n['id'] == notificationId,
      );
      if (notiIndex != -1) {
        _notifications[notiIndex]['is_read'] = true;
        notifyListeners();
      }
      return;
    }
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/notifications/$notificationId/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        final notiIndex = _notifications.indexWhere(
          (n) => n['id'] == notificationId,
        );
        if (notiIndex != -1) {
          _notifications[notiIndex]['is_read'] = true;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllNotificationsAsRead() async {
    if (_token.isEmpty || _token.startsWith('simulated')) {
      for (var n in _notifications) {
        n['is_read'] = true;
      }
      notifyListeners();
      return;
    }
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/notifications/read-all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        for (var n in _notifications) {
          n['is_read'] = true;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  void startNotificationsListener() {
    stopNotificationsListener();
    if (_token.isEmpty) return;

    _isNotiListenerConnected = true;
    try {
      String currentWsBase = wsBaseUrl;
      if (apiBaseUrl.contains('localhost') ||
          apiBaseUrl.contains('127.0.0.1') ||
          apiBaseUrl.contains('10.0.2.2') ||
          apiBaseUrl.contains('192.168.')) {
        try {
          final uri = Uri.parse(apiBaseUrl);
          final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
          currentWsBase = '$scheme://${uri.host}:${uri.port}/api/v1/ws';
        } catch (_) {}
      }

      final cleanWsBase = currentWsBase.endsWith('/ws')
          ? currentWsBase.substring(0, currentWsBase.length - 3)
          : currentWsBase;
      final wsUrl = '$cleanWsBase/notifications/ws?token=$_token';
      _notificationsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _notificationsChannel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message);
            _notifications.insert(0, data);
            notifyListeners();

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
          debugPrint('Notification WS error: $err');
          _isNotiListenerConnected = false;
        },
        onDone: () {
          _isNotiListenerConnected = false;
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Notification WS connection failed: $e');
      _isNotiListenerConnected = false;
    }
  }

  void stopNotificationsListener() {
    _notificationsChannel?.sink.close();
    _notificationsChannel = null;
    _isNotiListenerConnected = false;
  }

  Future<void> loadProfile() async {
    if (_token.isEmpty || _token.startsWith('simulated')) return;
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/auth/me'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _userName = data['full_name'] ?? _userName;
        _userPhone = data['phone_number'] ?? _userPhone;
        _userNic = data['nic_number'] ?? '';
        _userGender = data['gender'] ?? '';
        if (data['role'] != null && data['role'].toString().isNotEmpty) {
          _role = data['role'].toString();
        }
        _saveSession();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<Map<String, dynamic>> fetchVehicleReviews(String vehicleId) async {
    if (vehicleId.isEmpty) {
      return {'average_rating': 0.0, 'total_reviews': 0, 'reviews': []};
    }
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/vehicles/$vehicleId/reviews'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Error fetching reviews: $e');
    }
    return {'average_rating': 0.0, 'total_reviews': 0, 'reviews': []};
  }

  Future<bool> submitVehicleReview(
    String vehicleId,
    int rating,
    String comment,
  ) async {
    if (vehicleId.isEmpty) return false;
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (_token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_token';
      }
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/vehicles/$vehicleId/reviews'),
            headers: headers,
            body: json.encode({
              'rating': rating,
              'comment': comment,
              'passenger_name': _userName.isNotEmpty ? _userName : 'Passenger',
            }),
          )
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('Error submitting review: $e');
      return false;
    }
  }

  Future<bool> updateProfile(
    String name,
    String nic,
    String gender,
    String phone,
  ) async {
    // Local updates
    _userName = name;
    _userNic = nic;
    _userGender = gender;
    _userPhone = phone;
    _saveSession();
    notifyListeners();

    if (_token.isEmpty || _token.startsWith('simulated')) return true;
    try {
      final response = await http
          .put(
            Uri.parse('$apiBaseUrl/auth/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
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
        _userName = data['full_name'] ?? _userName;
        _userNic = data['nic_number'] ?? _userNic;
        _userGender = data['gender'] ?? _userGender;
        _userPhone = data['phone_number'] ?? _userPhone;
        _saveSession();
        notifyListeners();
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
    _isAuthenticated = false;
    _token = '';
    _selectedSeats.clear();
    _bookedSeats.clear();
    _heldSeats.clear();
    _notifications.clear();
    stopTracking();
    stopStreamingGPS();
    stopNotificationsListener();
    _saveSession();
    notifyListeners();
  }

  // Load vehicles from backend
  Future<void> loadVehicles() async {
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/vehicles'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _vehicles.clear();
        for (var item in data) {
          _vehicles.add(item as Map<String, dynamic>);
        }
        notifyListeners();
      } else if (response.statusCode == 401) {
        logout();
      }
    } catch (e) {
      debugPrint('Error loading vehicles: $e');
    }
  }

  // ---- CONDUCTORS (Owner's crew) ----
  final List<Map<String, dynamic>> _conductorsList = [];
  List<Map<String, dynamic>> get conductorsList => _conductorsList;

  Future<void> loadConductors() async {
    if (_token.isEmpty || _token.startsWith('simulated')) return;
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/conductors'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _conductorsList.clear();
        for (var item in data) {
          if (item is Map<String, dynamic>) {
            _conductorsList.add(item);
          }
        }
        _saveConductorsToPrefs();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading conductors: $e');
    }
  }

  Future<Map<String, dynamic>?> addConductor(String name, String phone) async {
    final newConductor = {
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'full_name': name,
      'phone_number': phone,
      'role': 'conductor',
    };
    _conductorsList.add(newConductor);
    _saveConductorsToPrefs();
    notifyListeners();
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/conductors'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: json.encode({'full_name': name, 'phone_number': phone}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _conductorsList.remove(newConductor);
        _conductorsList.add(data);
        _saveConductorsToPrefs();
        notifyListeners();
        return data;
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['detail'] ?? 'Failed to add conductor');
      }
    } catch (e) {
      _conductorsList.remove(newConductor);
      _saveConductorsToPrefs();
      notifyListeners();
      debugPrint('Error adding conductor: $e');
      rethrow;
    }
  }

  Future<bool> deleteConductor(String conductorId) async {
    if (_token.isEmpty || _token.startsWith('simulated')) {
      _conductorsList.removeWhere((c) => c['id'].toString() == conductorId);
      notifyListeners();
      return true;
    }
    try {
      final response = await http
          .delete(
            Uri.parse('$apiBaseUrl/conductors/$conductorId'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 204 || response.statusCode == 200) {
        _conductorsList.removeWhere((c) => c['id'].toString() == conductorId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting conductor: $e');
    }
    return false;
  }

  // Load trips from backend
  Future<void> loadTrips({String? date}) async {
    try {
      final Map<String, String> headers = {};
      if (_token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_token';
      }
      final queryDate = date ??
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      final response = await http
          .get(Uri.parse('$apiBaseUrl/trips?date=$queryDate'), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _trips.clear();
        for (var item in data) {
          final tripMap = item as Map<String, dynamic>;
          final vehicle = tripMap['vehicle'] ?? {};
          _trips.add({
            'id': tripMap['id'],
            'vehicle_id': vehicle['id'] ?? tripMap['vehicle_id'],
            'origin': tripMap['route']?['origin'] ?? 'Colombo Fort',
            'destination': tripMap['route']?['destination'] ?? 'Galle',
            'route': tripMap['route'],
            'departure':
                tripMap['departure_time']
                    ?.toString()
                    .replaceAll('T', ' ')
                    .substring(0, 16) ??
                '2026-07-13 14:00',
            'price':
                double.tryParse(tripMap['price_per_seat'].toString()) ?? 1600.0,
            'bus_name': vehicle['name'] ?? 'Luxury Express',
            'reg': vehicle['registration_number'] ?? 'WP-ND-0000',
            'total_seats': vehicle['total_seats'] ?? 40,
            'seat_layout': vehicle['seat_layout'],
            'amenities': List<String>.from(vehicle['amenities'] ?? []),
            'booked_seats': List<String>.from(tripMap['booked_seats'] ?? []),
            'boarded_seats': List<String>.from(tripMap['boarded_seats'] ?? []),
            'arrival': tripMap['arrival_time']?.toString().replaceAll('T', ' ').substring(0, 16) ?? '',
          });
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading trips: $e');
    }
  }

  // Load bookings from backend
  Future<void> loadBookings() async {
    if (_token.isEmpty || _token.startsWith('simulated')) return;
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/bookings'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _bookings.clear();
        for (var item in data) {
          final b = item as Map<String, dynamic>;
          final trip = b['trip'] ?? {};
          final vehicle = trip['vehicle'] ?? {};
          _bookings.add({
            'id': b['id'],
            'trip_id': b['trip_id'],
            'origin': trip['route']?['origin'] ?? 'Colombo Fort',
            'destination': trip['route']?['destination'] ?? 'Galle',
            'departure':
                trip['departure_time']
                    ?.toString()
                    .replaceAll('T', ' ')
                    .substring(0, 16) ??
                '2026-07-13 14:00',
            'bus_name': vehicle['name'] ?? 'Luxury Express',
            'reg': vehicle['registration_number'] ?? 'WP-ND-0000',
            'seats': List<String>.from(b['selected_seats'] ?? []),
            'price': double.tryParse(b['total_price'].toString()) ?? 0.0,
            'status': b['booking_status'] ?? 'pending',
            'passenger_name': b['passenger']?['full_name'] ?? 'Passenger',
            'boarded_seats': List<String>.from(trip['boarded_seats'] ?? []),
            'passenger_details': b['passenger_details'] ?? {},
          });
        }
        notifyListeners();
      } else if (response.statusCode == 401) {
        logout();
      }
    } catch (e) {
      debugPrint('Error loading bookings: $e');
    }
  }

  // Load seat availability for a trip
  Future<void> loadSeatAvailability(String tripId, {bool clearFirst = false}) async {
    if (clearFirst) {
      _bookedSeats.clear();
      _heldSeats.clear();
      _seatGenders.clear();
      notifyListeners();
    }

    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/seat-holds/trip/$tripId'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _bookedSeats = List<String>.from(data['booked_seats'] ?? []);
        _heldSeats = List<String>.from(data['held_seats'] ?? []);
        if (data['seat_genders'] != null) {
          _seatGenders = Map<String, String>.from(data['seat_genders']);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading seat availability: $e');
    }
  }

  // Fetch detailed manifest for conductors
  Future<Map<String, dynamic>?> fetchTripManifest(String tripId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/trips/$tripId/manifest'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Error fetching manifest: $e');
    }
    return null;
  }

  // Fetch details of a specific booking by ID
  Future<Map<String, dynamic>?> fetchBookingDetails(String bookingId) async {
    if (_token.isEmpty || _token.startsWith('simulated')) {
      try {
        final b = _bookings.firstWhere(
          (item) => item['id'].toString().toLowerCase() == bookingId.toLowerCase(),
        );
        return b;
      } catch (e) {
        return null;
      }
    }
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/bookings/$bookingId'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final b = json.decode(response.body) as Map<String, dynamic>;
        final trip = b['trip'] ?? {};
        final vehicle = trip['vehicle'] ?? {};
        return {
          'id': b['id'],
          'trip_id': b['trip_id'],
          'origin': trip['route']?['origin'] ?? 'Colombo Fort',
          'destination': trip['route']?['destination'] ?? 'Galle',
          'departure':
              trip['departure_time']
                  ?.toString()
                  .replaceAll('T', ' ')
                  .substring(0, 16) ??
              '2026-07-13 14:00',
          'bus_name': vehicle['name'] ?? 'Luxury Express',
          'reg': vehicle['registration_number'] ?? 'WP-ND-0000',
          'seats': List<String>.from(b['selected_seats'] ?? []),
          'price': double.tryParse(b['total_price'].toString()) ?? 0.0,
          'status': b['booking_status'] ?? 'pending',
          'passenger_name': b['passenger']?['full_name'] ?? 'Passenger',
          'boarded_seats': List<String>.from(trip['boarded_seats'] ?? []),
          'passenger_details': b['passenger_details'] ?? {},
        };
      }
    } catch (e) {
      debugPrint('Error fetching booking details: $e');
    }
    return null;
  }

  // Toggle boarding status of a seat
  Future<List<String>?> toggleBoarding(String tripId, String seat, {String? action}) async {
    try {
      final queryParams = action != null ? '?seat=$seat&action=$action' : '?seat=$seat';
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/trips/$tripId/toggle-board$queryParams'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<String>.from(data['boarded_seats'] ?? []);
      } else {
        final data = json.decode(response.body);
        final errorMsg = data['detail'] ?? 'Failed to toggle boarding';
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint('Error toggling boarding: $e');
      rethrow;
    }
  }

  // Initiate Booking (creates pending booking and holds seats)
  Future<Map<String, dynamic>?> initiateBooking(
    String tripId,
    Map<String, dynamic> passengerDetails,
  ) async {
    if (_selectedSeats.isEmpty) return null;

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'trip_id': tripId,
          'selected_seats': _selectedSeats,
          'passenger_details': passengerDetails,
        }),
      );

      if (response.statusCode == 201) {
        final bookingData = json.decode(response.body);
        return bookingData;
      } else if (response.statusCode == 401) {
        logout();
      }
    } catch (e) {
      debugPrint('Error initiating booking: $e');
    }
    return null;
  }

  // Initiate Payment
  Future<Map<String, dynamic>?> initiatePayment(String bookingId) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/payments/initiate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'booking_id': bookingId}),
      );

      if (response.statusCode == 201) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Error initiating payment: $e');
    }
    return null;
  }

  // Complete Sandbox Payment
  Future<bool> completeSandboxPayment(String transactionId) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/payments/sandbox/complete/$transactionId'),
      );
      if (response.statusCode == 200) {
        _selectedSeats.clear();
        await loadBookings();
        return true;
      }
    } catch (e) {
      debugPrint('Error completing sandbox payment: $e');
    }
    return false;
  }

  // Fail Sandbox Payment
  Future<bool> failSandboxPayment(String transactionId) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/payments/sandbox/fail/$transactionId'),
      );
      if (response.statusCode == 200) {
        _selectedSeats.clear();
        await loadBookings();
        return true;
      }
    } catch (e) {
      debugPrint('Error failing sandbox payment: $e');
    }
    return false;
  }

  // Add vehicle
  void registerVehicle(String name, String reg, int capacity) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/vehicles'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'name': name,
          'registration_number': reg,
          'type': 'bus',
          'seat_layout': {
            'rows': (capacity / 4).ceil(),
            'columns': 4,
            'aisle_after_column': 2,
          },
          'total_seats': capacity,
          'amenities': ['AC', 'WiFi', 'Charging Ports', 'Reclining Seats'],
        }),
      );
      if (response.statusCode == 201) {
        await loadVehicles();
        return;
      }
    } catch (e) {
      debugPrint('Error registering vehicle: $e');
    }

    // Local fallback
    _vehicles.add({
      'id': 'v-${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'reg': reg,
      'total_seats': capacity,
      'is_verified': false,
    });
    notifyListeners();
  }

  // Add trip
  void scheduleTrip(
    String vehicleId,
    String origin,
    String destination,
    String time,
    double price,
  ) async {
    try {
      // Find the vehicle UUID from our list of vehicles
      final v = _vehicles.firstWhere(
        (x) => x['id'] == vehicleId || x['reg'] == vehicleId,
        orElse: () => _vehicles[0],
      );

      // We need a route. We can fetch or create a route, or post to trips.
      // Let's create/retrieve a route first
      final routeResponse = await http.post(
        Uri.parse('$apiBaseUrl/routes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'origin': origin,
          'destination': destination,
          'total_distance': 120.0,
          'estimated_duration_seconds': 7200,
        }),
      );

      if (routeResponse.statusCode == 201) {
        final routeData = json.decode(routeResponse.body);
        final routeId = routeData['id'];

        final tripResponse = await http.post(
          Uri.parse('$apiBaseUrl/trips'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_token',
          },
          body: json.encode({
            'vehicle_id': v['id'],
            'route_id': routeId,
            'departure_time': DateTime.parse(
              time.replaceAll(' ', 'T') + ':00Z',
            ).toUtc().toIso8601String(),
            'arrival_time': DateTime.parse(
              time.replaceAll(' ', 'T') + ':00Z',
            ).add(const Duration(hours: 2)).toUtc().toIso8601String(),
            'price_per_seat': price,
          }),
        );

        if (tripResponse.statusCode == 201) {
          await loadTrips();
          return;
        }
      }
    } catch (e) {
      debugPrint('Error scheduling trip: $e');
    }

    // Local fallback
    final v = _vehicles.firstWhere(
      (x) => x['id'] == vehicleId || x['reg'] == vehicleId,
      orElse: () => _vehicles[0],
    );
    _trips.add({
      'id': 't-${DateTime.now().millisecondsSinceEpoch}',
      'origin': origin,
      'destination': destination,
      'departure': time,
      'price': price,
      'bus_name': v['name'],
      'reg': v['reg'],
      'amenities': List<String>.from(
        v['amenities'] ?? ['AC', 'WiFi', 'Charging Ports', 'Reclining Seats'],
      ),
    });
    notifyListeners();
  }

  // Seats interactions
  void selectSeatWithGender(String seatLabel, String gender) {
    if (!_selectedSeats.contains(seatLabel)) {
      _selectedSeats.add(seatLabel);
    }
    _selectedSeatGenders[seatLabel] = gender;
    notifyListeners();
  }

  void deselectSeat(String seatLabel) {
    _selectedSeats.remove(seatLabel);
    _selectedSeatGenders.remove(seatLabel);
    notifyListeners();
  }

  void clearSelectedSeats() {
    _selectedSeats.clear();
    _selectedSeatGenders.clear();
    notifyListeners();
  }

  // Local fallback confirmation
  void bookTicket(Map<String, dynamic> trip) {
    if (_selectedSeats.isEmpty) return;

    _bookings.insert(0, {
      'id': 'b-${DateTime.now().millisecondsSinceEpoch}',
      'trip_id': trip['id'],
      'origin': trip['origin'],
      'destination': trip['destination'],
      'departure': trip['departure'],
      'bus_name': trip['bus_name'],
      'reg': trip['reg'],
      'seats': List<String>.from(_selectedSeats),
      'price': trip['price'] * _selectedSeats.length,
      'status': 'confirmed',
    });
    _selectedSeats.clear();
    notifyListeners();
  }

  // Live Tracking listener (WS Client)
  void startTracking(String vehicleId) {
    stopTracking();
    _isTracking = true;
    _trackedBusLocation = null;
    notifyListeners();

    try {
      final wsUrl =
          '$wsBaseUrl/tracking/$vehicleId?role=passenger&token=$_token';
      _trackingChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _trackingChannel!.stream.listen(
        (message) {
          final data = json.decode(message);
          _trackedBusLocation = data;
          notifyListeners();
        },
        onError: (err) {
          debugPrint('Tracking socket error: $err');
          stopTracking();
        },
        onDone: () {
          stopTracking();
        },
      );
    } catch (e) {
      debugPrint(
        'WebSocket connection failed: $e.',
      );
      stopTracking();
    }
  }

  void _startLocalTrackingSimulation(
    String vehicleId,
    double startLat,
    double startLon,
    double destLat,
    double destLon,
  ) {
    _trackingTimer?.cancel();
    double currentLat = startLat;
    double currentLon = startLon;

    // Move in 50 steps
    final double latStep = (destLat - startLat) / 50;
    final double lonStep = (destLon - startLon) / 50;

    _trackingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isTracking) {
        timer.cancel();
        return;
      }

      currentLat += latStep;
      currentLon += lonStep;

      // Reset to start if near destination
      if ((currentLat - destLat).abs() < 0.02 &&
          (currentLon - destLon).abs() < 0.02) {
        currentLat = startLat;
        currentLon = startLon;
      }

      _trackedBusLocation = {
        'vehicle_id': vehicleId,
        'latitude': currentLat,
        'longitude': currentLon,
        'speed': 62.5,
        'heading': 165.0,
      };
      notifyListeners();
    });
  }

  void stopTracking() {
    _trackingChannel?.sink.close();
    _trackingChannel = null;
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _isTracking = false;
    _trackedBusLocation = null;
    notifyListeners();
  }

  // Location streaming sender (WS Client)
  Future<void> startStreamingGPS(String vehicleId, bool simulate) async {
    stopStreamingGPS();
    _isStreamingGPS = true;
    notifyListeners();

    // Initialize socket connection
    try {
      final wsUrl = '$wsBaseUrl/tracking/$vehicleId?role=driver&token=$_token';
      _streamingChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    } catch (e) {
      print('Streaming socket connection failed: $e');
    }

    // Active GPS streaming
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _isStreamingGPS = false;
      notifyListeners();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _isStreamingGPS = false;
        notifyListeners();
        return;
      }
    }

    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) {
          final payload = {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'speed': position.speed * 3.6, // m/s to km/h
            'heading': position.heading,
          };

          _streamingChannel?.sink.add(json.encode(payload));
          notifyListeners();
        });
  }

  void stopStreamingGPS() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _streamingChannel?.sink.close();
    _streamingChannel = null;
    _isStreamingGPS = false;
    notifyListeners();
  }
}

// =====================================================================
// CUSTOM NOTIFICATION MANAGER (Toast / SnackBar Replacement)
// =====================================================================
class SeatyNotifications {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();

    final Color bgColor = isError
        ? const Color(0xFFEF4444) // Soft Red
        : isWarning
        ? const Color(0xFFF59E0B) // Amber/Orange
        : const Color(0xFF10B981); // Emerald Green

    final IconData icon = isError
        ? Icons.error_outline_rounded
        : isWarning
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: duration,
      ),
    );
  }
}

// =====================================================================
// 2. MAIN APPLICATION SETUP
// =====================================================================
late final SharedPreferences globalPrefs;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final appStateProvider = ChangeNotifierProvider<AppState>((ref) {
  return AppState(globalPrefs);
});

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    setupPushNotifications();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  globalPrefs = await SharedPreferences.getInstance();
  runApp(const ProviderScope(child: SeatyApp()));
}

class SeatyApp extends StatelessWidget {
  const SeatyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Seaty Luxury Transport',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        primaryColor: const Color(0xFF0A2540), // Navy Blue
        hintColor: const Color(0xFF2563EB), // Blue (matches admin dashboard)
        cardColor: const Color(0xFFF8FAFC), // Slate off-white (matches admin)
        fontFamily: GoogleFonts.poppins().fontFamily,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0A2540),
          secondary: Color(0xFF2563EB),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF0A2540)),
          titleTextStyle: TextStyle(
            color: Color(0xFF0A2540),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF2563EB),
          unselectedItemColor: Color(0xFF64748B),
          elevation: 8,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// =====================================================================
// DART-LEVEL SPLASH SCREEN (Shows on every Hot Restart)
// =====================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Image.asset(
            'assets/images/app_logo.png',
            height: 320,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.explore_rounded,
              size: 80,
              color: Color(0xFF6366F1),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 3. AUTHENTICATION & WRAPPER SCREEN (Role Selection Screen)
// =====================================================================
class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    if (!state.isAuthenticated) {
      return const PhoneAuthScreen();
    }
    final userRole = state.role.toLowerCase();
    if (userRole == 'owner') {
      return const OwnerMainScreen();
    } else if (userRole == 'conductor') {
      return const ConductorMainScreen();
    } else {
      return const PassengerMainScreen();
    }
  }
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Display app_logo.png instead of app_icon.png
              Image.asset(
                'assets/images/app_logo.png',
                height: 190,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.explore_rounded,
                  size: 80,
                  color: Color(0xFF0A2540),
                ),
              ),
              const SizedBox(height: 48),

              const Text(
                'Select Your Account Role',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A2540),
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'Choose how you want to proceed into Seaty',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 36),

              // Role selection cards
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Row(
                  children: [
                    // Passenger Card
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const PhoneAuthScreen(initialRole: 'passenger'),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F6F9),
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Image.asset(
                                'assets/images/passenger_icon.png',
                                height: 85,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.directions_bus_rounded,
                                      size: 48,
                                      color: Color(0xFF0A2540),
                                    ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Passenger',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF0A2540),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Book & track luxury buses',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Owner Card
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const PhoneAuthScreen(initialRole: 'owner'),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F6F9),
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Image.asset(
                                'assets/images/owner_icon.png',
                                height: 85,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.airport_shuttle_rounded,
                                      size: 48,
                                      color: Color(0xFF0A2540),
                                    ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Owner',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF0A2540),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Confirm & manage bookings',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// MOBILE & OTP AUTHENTICATION PROCESS
// =====================================================================
enum PhoneAuthState { enterPhone, register, verifyOtp }

class PhoneAuthScreen extends ConsumerStatefulWidget {
  final String? initialRole;
  const PhoneAuthScreen({super.key, this.initialRole});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  PhoneAuthState _authState = PhoneAuthState.enterPhone;
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();
  String _generatedOtp = '';
  bool _isNewUser = false;
  String _currentUserName = '';
  late String _dynamicRole;

  @override
  void initState() {
    super.initState();
    _dynamicRole = widget.initialRole ?? 'passenger';
  }

  void _generateAndSendOtp(BuildContext context, String name, String phone) {
    final random = DateTime.now().millisecondsSinceEpoch % 1000000;
    _generatedOtp = random.toString().padLeft(6, '0');
    _otpController.text = _generatedOtp; // Auto-complete verification code

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.sms_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'SMS: Seaty Verification Code',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Your OTP code is: $_generatedOtp'),
                    ],
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 10),
            backgroundColor: const Color(0xFF0A2540),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.read(appStateProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _authState == PhoneAuthState.enterPhone
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Color(0xFF0A2540),
                  size: 36,
                ),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  if (_authState == PhoneAuthState.register) {
                    setState(() => _authState = PhoneAuthState.enterPhone);
                  } else if (_authState == PhoneAuthState.verifyOtp) {
                    if (_isNewUser) {
                      setState(() => _authState = PhoneAuthState.register);
                    } else {
                      setState(() => _authState = PhoneAuthState.enterPhone);
                    }
                  }
                },
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildStateContent(state),
          ),
        ),
      ),
    );
  }

  Widget _buildStateContent(AppState state) {
    switch (_authState) {
      case PhoneAuthState.enterPhone:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              height: 100,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.phone_iphone_rounded,
                size: 64,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Welcome to Seaty',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter your mobile number to receive verification code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                hintText: 'e.g. 0771234567',
                prefixIcon: const Icon(
                  Icons.phone_iphone_rounded,
                  color: Color(0xFF0A2540),
                ),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A2540),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final phone = _phoneController.text.trim();
                if (phone.length < 9) {
                  SeatyNotifications.show(
                    context,
                    'Please enter a valid mobile number.',
                    isError: true,
                  );
                  return;
                }

                // Show loading SnackBar or call API
                SeatyNotifications.show(
                  context,
                  'Verifying number...',
                  duration: const Duration(milliseconds: 600),
                );

                final checkResult = await state.checkPhoneDB(
                  phone,
                  preferredRole: widget.initialRole,
                );
                final bool exists = checkResult['exists'] ?? false;
                final String name = checkResult['name'] ?? 'Guest User';
                _dynamicRole = checkResult['role'] ?? 'passenger';

                if (exists) {
                  _isNewUser = false;
                  _currentUserName = name;
                  _generateAndSendOtp(context, name, phone);
                  setState(() => _authState = PhoneAuthState.verifyOtp);
                } else {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _isNewUser = true;
                    _dynamicRole = widget.initialRole ?? 'passenger';
                    _nameController.clear();
                    _authState = PhoneAuthState.register;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            if (_dynamicRole == 'passenger') ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() {
                        _isNewUser = true;
                        _nameController.clear();
                        _authState = PhoneAuthState.register;
                      });
                    },
                    child: const Text(
                      'Register Now',
                      style: TextStyle(
                        color: Color(0xFF0A2540),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );

      case PhoneAuthState.register:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              height: 100,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.person_add_rounded,
                size: 64,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Register Account',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Create a new Seaty account using your mobile number',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              keyboardType: TextInputType.text,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Full Name',
                hintText: 'Enter your full name',
                prefixIcon: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF0A2540),
                ),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A2540),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                prefixIcon: const Icon(
                  Icons.phone_iphone_rounded,
                  color: Color(0xFF0A2540),
                ),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A2540),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final name = _nameController.text.trim();
                final phone = _phoneController.text.trim();
                if (name.isEmpty) {
                  SeatyNotifications.show(
                    context,
                    'Please enter your full name.',
                    isError: true,
                  );
                  return;
                }
                if (phone.length < 9) {
                  SeatyNotifications.show(
                    context,
                    'Please enter a valid mobile number.',
                    isError: true,
                  );
                  return;
                }

                FocusScope.of(context).unfocus();
                // Show loading SnackBar or call API
                SeatyNotifications.show(
                  context,
                  'Creating account...',
                  duration: const Duration(milliseconds: 600),
                );

                _dynamicRole = 'passenger';
                await state.registerPhoneDB(name, phone, 'passenger');
                _isNewUser = true;
                _currentUserName = name;
                _generateAndSendOtp(context, name, phone);
                setState(() => _authState = PhoneAuthState.verifyOtp);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Register & Verify',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Already have an account? ",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                TextButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _isNewUser = false;
                      _authState = PhoneAuthState.enterPhone;
                    });
                  },
                  child: const Text(
                    'Login',
                    style: TextStyle(
                      color: Color(0xFF0A2540),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case PhoneAuthState.verifyOtp:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              height: 100,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.mark_email_read_rounded,
                size: 64,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Enter OTP Code',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the 6-digit code sent to ${_phoneController.text}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                color: Colors.black87,
                letterSpacing: 8,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: '••••••',
                hintStyle: const TextStyle(
                  letterSpacing: 8,
                  color: Colors.grey,
                ),
                counterText: '',
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A2540),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final otp = _otpController.text.trim();
                if (otp != _generatedOtp) {
                  SeatyNotifications.show(
                    context,
                    'Invalid verification code. Please check the SMS.',
                    isError: true,
                  );
                  return;
                }

                final phone = _phoneController.text.trim();
                final name = _currentUserName.isNotEmpty
                    ? _currentUserName
                    : 'User';
                state.login(name, _dynamicRole, phone);
                _otpController.clear();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Verify & Login',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                final phone = _phoneController.text.trim();
                final name = _currentUserName.isNotEmpty
                    ? _currentUserName
                    : 'User';
                _generateAndSendOtp(context, name, phone);
                SeatyNotifications.show(context, 'A new OTP has been sent.');
              },
              child: const Text(
                'Resend Code',
                style: TextStyle(
                  color: Color(0xFF0A2540),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
    }
  }
}

// =====================================================================
// 4. PASSENGER MAIN SCREEN
// =====================================================================
class PassengerMainScreen extends ConsumerStatefulWidget {
  const PassengerMainScreen({super.key});

  @override
  ConsumerState<PassengerMainScreen> createState() =>
      _PassengerMainScreenState();
}

class _PassengerMainScreenState extends ConsumerState<PassengerMainScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const PassengerTripsTab(),
    const PassengerTrackingTab(),
    const PassengerBookingsTab(),
    const ProfileEditScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true, // Let content scroll behind the floating capsule
      extendBodyBehindAppBar: true,
      body: _tabs[_currentIndex],
      bottomNavigationBar: _buildTelegramBottomNavBar(context),
    );
  }

  Widget _buildTelegramBottomNavBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 32, right: 32, bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Premium Dark Slate
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
          _buildNavItem(
            1,
            Icons.near_me_outlined,
            Icons.near_me_rounded,
            'Tracker',
          ),
          _buildNavItem(
            2,
            Icons.receipt_long_outlined,
            Icons.receipt_long_rounded,
            'Tickets',
          ),
          _buildNavItem(
            3,
            Icons.person_outline_rounded,
            Icons.person_rounded,
            'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData outlineIcon,
    IconData solidIcon,
    String label,
  ) {
    final isSelected = _currentIndex == index;
    final activeColor = Colors.white;
    final activeBgColor = const Color(0xFF2563EB); // Matte Orange
    final inactiveColor = Colors.white.withOpacity(0.75);

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuint,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuint,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? solidIcon : outlineIcon,
                color: isSelected ? activeColor : inactiveColor,
                size: 24,
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Sub-Tab 1: Passenger Trips & Booking Flow
class PassengerTripsTab extends ConsumerStatefulWidget {
  const PassengerTripsTab({super.key});

  @override
  ConsumerState<PassengerTripsTab> createState() => _PassengerTripsTabState();
}

class _PassengerTripsTabState extends ConsumerState<PassengerTripsTab>
    with WidgetsBindingObserver {
  String _selectedFrom = 'All';
  String _selectedTo = 'All';
  DateTime? _selectedDate;

  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final TextEditingController _dateController;
  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();

  VideoPlayerController? _videoController;
  late final ScrollController _scrollController;
  double _headerOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    _fromController = TextEditingController(text: _selectedFrom);
    _toController = TextEditingController(text: _selectedTo);
    _dateController = TextEditingController(text: 'All Dates');
    _fromFocusNode.addListener(_onFocusChange);
    _toFocusNode.addListener(_onFocusChange);
    _initVideoBackground();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_videoController != null && !_videoController!.value.isPlaying) {
        _videoController?.play();
      }
    }
  }

  void _initVideoBackground() {
    _videoController =
        VideoPlayerController.asset(
            'assets/videos/bg_travel.mp4',
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          )
          ..initialize()
              .then((_) {
                if (mounted) {
                  setState(() {});
                  _videoController?.setLooping(true);
                  _videoController?.setVolume(0.0);
                  _videoController?.play();
                }
              })
              .catchError((e) {
                debugPrint('Error loading bg video: $e');
              });
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final newOpacity = (offset / 100.0).clamp(0.0, 1.0);
    if (newOpacity != _headerOpacity) {
      setState(() {
        _headerOpacity = newOpacity;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _videoController?.dispose();
    _fromController.dispose();
    _toController.dispose();
    _dateController.dispose();
    _fromFocusNode.removeListener(_onFocusChange);
    _toFocusNode.removeListener(_onFocusChange);
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    super.dispose();
  }

  // Palette pool for dynamic destination cards
  static const List<List<int>> _colorPalette = [
    [0xFF0A2540, 0xFF0E3A5E],
    [0xFF2563EB, 0xFFFF8A50],
    [0xFF1E293B, 0xFF475569],
    [0xFF7C3AED, 0xFF9F6FFF],
    [0xFF0F766E, 0xFF14B8A6],
    [0xFFB45309, 0xFFD97706],
    [0xFF1D4ED8, 0xFF3B82F6],
    [0xFF9D174D, 0xFFEC4899],
  ];

  static const List<IconData> _iconPool = [
    Icons.location_city_rounded,
    Icons.temple_buddhist_rounded,
    Icons.beach_access_rounded,
    Icons.landscape_rounded,
    Icons.forest_rounded,
    Icons.train_rounded,
    Icons.directions_bus_rounded,
    Icons.place_rounded,
  ];

  List<Map<String, dynamic>> _getDestinations(
    List<Map<String, dynamic>> trips,
  ) {
    final topDestinations = [
      'Colombo',
      'Kandy',
      'Galle',
      'Ella',
      'Trincomalee',
      'Anuradhapura',
    ];
    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < topDestinations.length; i++) {
      final idx = i % _colorPalette.length;
      result.add({
        'name': topDestinations[i],
        'color1': _colorPalette[idx][0],
        'color2': _colorPalette[idx][1],
        'icon': _iconPool[idx % _iconPool.length],
        'asset':
            'assets/images/destinations/${topDestinations[i].toLowerCase()}.jpg',
      });
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final headerContentColor =
        Color.lerp(Colors.white, Colors.black, _headerOpacity) ?? Colors.white;

    final allTrips = state.trips;
    final Set<String> placesSet = {'All'};
    for (final trip in allTrips) {
      if (trip['origin'] != null) placesSet.add(trip['origin'].toString());
      if (trip['destination'] != null)
        placesSet.add(trip['destination'].toString());
      final routeObj = trip['route'];
      if (routeObj != null && routeObj['stops'] != null) {
        for (final stop in routeObj['stops'] as List<dynamic>) {
          final stopName = stop['name']?.toString();
          if (stopName != null) placesSet.add(stopName);
        }
      }
    }
    final List<String> allPlaces = placesSet.toList()
      ..sort((a, b) {
        if (a == 'All') return -1;
        if (b == 'All') return 1;
        return a.compareTo(b);
      });

    final filteredTrips = state.trips.where((trip) {
      final hasFrom =
          _selectedFrom.isNotEmpty && _selectedFrom.toLowerCase() != 'all';
      final hasTo =
          _selectedTo.isNotEmpty && _selectedTo.toLowerCase() != 'all';
      final hasDate = _selectedDate != null;
      if (!hasFrom && !hasTo && !hasDate) return true;

      // Helper to find position of a location (-1 = origin, index = stop index, 100000 = destination)
      int? findStopPos(String searchLoc) {
        final normSearch = searchLoc.toLowerCase().trim();
        if (normSearch.isEmpty) return null;
        final normOrigin = trip['origin']?.toString().toLowerCase() ?? '';
        final normDest = trip['destination']?.toString().toLowerCase() ?? '';

        if (normOrigin.contains(normSearch)) return -1;

        // Check intermediate stops if route details are present
        final routeObj = trip['route'];
        if (routeObj != null && routeObj['stops'] != null) {
          final stops = routeObj['stops'] as List<dynamic>;
          for (int i = 0; i < stops.length; i++) {
            final stopName = stops[i]['name']?.toString().toLowerCase() ?? '';
            if (stopName.contains(normSearch)) {
              return i;
            }
          }
        }

        if (normDest.contains(normSearch)) return 100000;
        return null;
      }

      bool match = true;
      int? fromPos;
      int? toPos;

      if (hasFrom) {
        fromPos = findStopPos(_selectedFrom);
        if (fromPos == null) match = false;
      }

      if (hasTo) {
        toPos = findStopPos(_selectedTo);
        if (toPos == null) match = false;
      }

      // Ensure origin comes before destination
      if (match && hasFrom && hasTo) {
        if (fromPos != null && toPos != null && fromPos >= toPos) {
          match = false;
        }
      }

      // Filter by date if specified
      if (match && hasDate) {
        final departureStr = trip['departure']?.toString() ?? '';
        if (departureStr.isNotEmpty) {
          try {
            final datePart = departureStr
                .split(' ')[0]
                .trim(); // e.g., '2026-07-13'
            final selectedDateStr =
                "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";
            if (datePart != selectedDateStr) {
              match = false;
            }
          } catch (e) {
            match = false;
          }
        } else {
          match = false;
        }
      }

      return match;
    }).toList();

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ─── Glassmorphic Hero & Search Header ───
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  // Background Video Player / Fallback Gradient
                  SizedBox(
                    height: 280,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_videoController != null &&
                              _videoController!.value.isInitialized)
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _videoController!.value.size.width,
                                height: _videoController!.value.size.height,
                                child: VideoPlayer(_videoController!),
                              ),
                            )
                          else
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF0F172A),
                                    Color(0xFF1E293B),
                                  ],
                                ),
                              ),
                            ),
                          // Dark overlay to ensure text readability over the video
                          Container(color: Colors.black.withOpacity(0.4)),
                        ],
                      ),
                    ),
                  ),
                  // Content
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Spacer for sticky header
                          const SizedBox(height: 48),
                          // Greeting + Search prompt
                          Text(
                            'Hello, ${state.userName} 👋',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Where are you\ntraveling today?',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Glassmorphic Search Bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF0F172A,
                                  ).withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.15),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _buildGlassField(
                                      icon: Icons.my_location_rounded,
                                      label: 'From',
                                      controller: _fromController,
                                      focusNode: _fromFocusNode,
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedFrom = val;
                                        });
                                      },
                                    ),
                                    if (_fromFocusNode.hasFocus)
                                      _buildSuggestionsList(
                                        query: _selectedFrom,
                                        places: allPlaces,
                                        onSelected: (val) {
                                          setState(() {
                                            _selectedFrom = val;
                                            _fromController.text = val;
                                            _fromFocusNode.unfocus();
                                          });
                                        },
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          const SizedBox(width: 20),
                                          Expanded(
                                            child: Container(
                                              height: 1,
                                              color: Colors.white.withOpacity(
                                                0.1,
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                final temp = _selectedFrom;
                                                _selectedFrom = _selectedTo;
                                                _selectedTo = temp;
                                                _fromController.text =
                                                    _selectedFrom;
                                                _toController.text =
                                                    _selectedTo;
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2563EB),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFF2563EB,
                                                    ).withOpacity(0.4),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.swap_vert_rounded,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              height: 1,
                                              color: Colors.white.withOpacity(
                                                0.1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _buildGlassField(
                                      icon: Icons.location_on_rounded,
                                      label: 'To',
                                      controller: _toController,
                                      focusNode: _toFocusNode,
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedTo = val;
                                        });
                                      },
                                    ),
                                    if (_toFocusNode.hasFocus)
                                      _buildSuggestionsList(
                                        query: _selectedTo,
                                        places: allPlaces,
                                        onSelected: (val) {
                                          setState(() {
                                            _selectedTo = val;
                                            _toController.text = val;
                                            _toFocusNode.unfocus();
                                          });
                                        },
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Container(
                                        height: 1,
                                        color: Colors.white.withOpacity(0.1),
                                      ),
                                    ),
                                    _buildGlassDateField(
                                      icon: Icons.calendar_today_rounded,
                                      label: 'Departure Date',
                                      controller: _dateController,
                                      onTap: () async {
                                        final DateTime?
                                        picked = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              _selectedDate ?? DateTime.now(),
                                          firstDate: DateTime.now().subtract(
                                            const Duration(days: 365),
                                          ),
                                          lastDate: DateTime.now().add(
                                            const Duration(days: 365),
                                          ),
                                          builder: (context, child) {
                                            return Theme(
                                              data: Theme.of(context).copyWith(
                                                colorScheme:
                                                    const ColorScheme.dark(
                                                      primary: Color(
                                                        0xFF2563EB,
                                                      ),
                                                      onPrimary: Colors.white,
                                                      surface: Color(
                                                        0xFF0F172A,
                                                      ),
                                                      onSurface: Colors.white,
                                                    ),
                                                dialogBackgroundColor:
                                                    const Color(0xFF0F172A),
                                              ),
                                              child: child!,
                                            );
                                          },
                                        );
                                        if (picked != null) {
                                          final dateStr = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                                          setState(() {
                                            _selectedDate = picked;
                                            _dateController.text = dateStr;
                                          });
                                          ref.read(appStateProvider).loadTrips(date: dateStr);
                                        }
                                      },
                                      onClear: () {
                                        setState(() {
                                          _selectedDate = null;
                                          _dateController.text = 'All Dates';
                                        });
                                        ref.read(appStateProvider).loadTrips();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),


            // ─── Ride Results Title ───
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filteredTrips.length} Rides Found',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── Floating Neumorphic Trip Cards ───
            if (filteredTrips.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.search_off_rounded,
                          size: 40,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No rides found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Try adjusting your search criteria',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: 120,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildModernTripCard(context, filteredTrips[index]);
                  }, childCount: filteredTrips.length),
                ),
              ),
          ],
        ),
        // Sticky Header with content-color scroll transition
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.transparent,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/app_icon.png',
                          width: 28,
                          height: 28,
                          color: headerContentColor,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.directions_bus_rounded,
                                  color: headerContentColor,
                                  size: 16,
                                ),
                              ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Seaty',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: headerContentColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                Icons.notifications_outlined,
                                color: headerContentColor,
                                size: 24,
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const NotificationsScreen(),
                                  ),
                                );
                              },
                            ),
                            if (state.unreadNotificationsCount > 0)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 14,
                                    minHeight: 14,
                                  ),
                                  child: Text(
                                    '${state.unreadNotificationsCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.9), size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: controller,
                focusNode: focusNode,
                cursorColor: Colors.white,
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                onChanged: onChanged,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  hintText: 'Type place...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGlassDateField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.9), size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (controller.text != 'All Dates')
                      GestureDetector(
                        onTap: () {
                          onClear();
                        },
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withOpacity(0.6),
                          size: 18,
                        ),
                      )
                    else
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withOpacity(0.5),
                        size: 20,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList({
    required String query,
    required List<String> places,
    required ValueChanged<String> onSelected,
  }) {
    final filtered = places.where((p) {
      if (query.isEmpty || query.toLowerCase() == 'all') return true;
      return p.toLowerCase().contains(query.toLowerCase());
    }).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final place = filtered[index];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => onSelected(place),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      place,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDestinationCard(
    String name,
    String subtitle,
    int color1,
    int color2,
    bool isSelected,
    bool isLight, {
    IconData? icon,
    String? assetImage,
  }) {
    // City-specific icon mapping
    final IconData cardIcon =
        icon ?? (isLight ? Icons.directions_bus_rounded : Icons.place_rounded);

    ImageProvider imgProvider;
    if (assetImage != null) {
      imgProvider = AssetImage(assetImage);
    } else {
      final String cleanName = name
          .replaceAll(RegExp(r'[^a-zA-Z]'), '')
          .toLowerCase();
      imgProvider = NetworkImage(
        name == 'All'
            ? 'https://loremflickr.com/400/400/srilanka,travel/all?lock=100'
            : 'https://loremflickr.com/400/400/$cleanName,srilanka/all?lock=${cleanName.hashCode.abs()}',
      );
    }

    final DecorationImage bgImage = DecorationImage(
      image: imgProvider,
      fit: BoxFit.cover,
      colorFilter: ColorFilter.mode(
        Colors.black.withOpacity(0.4),
        BlendMode.darken,
      ),
    );

    return GestureDetector(
      onTap: () => setState(() {
        _selectedTo = name;
        _toController.text = name;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: bgImage == null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(color1), Color(color2)],
                )
              : null,
          image: bgImage,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected && isLight
                ? const Color(0xFF2563EB)
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            if (isSelected && !isLight)
              BoxShadow(
                color: Color(color2).withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                cardIcon,
                color: isLight ? const Color(0xFF0F172A) : Colors.white,
                size: 20,
              ),
            ),
            const Spacer(),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isLight
                    ? const Color(0xFF64748B)
                    : Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isLight ? const Color(0xFF0F172A) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getAmenityIcon(String name, {Color color = const Color(0xFF64748B)}) {
    final String n = name.toLowerCase();
    IconData iconData = Icons.star_outline_rounded;

    if (n.contains('wifi')) {
      iconData = Icons.wifi_rounded;
    } else if (n.contains('charge') ||
        n.contains('charging') ||
        n.contains('plug') ||
        n.contains('outlet')) {
      iconData = Icons.power_rounded;
    } else if (n.contains('tv') ||
        n.contains('screen') ||
        n.contains('video') ||
        n.contains('hd tv')) {
      iconData = Icons.tv_rounded;
    } else if (n.contains('seat') ||
        n.contains('recline') ||
        n.contains('reclining')) {
      iconData = Icons.chair_rounded;
    } else if (n.contains('restroom') ||
        n.contains('toilet') ||
        n.contains('wc')) {
      iconData = Icons.wc_rounded;
    } else if (n.contains('luggage') ||
        n.contains('baggage') ||
        n.contains('bag') ||
        n.contains('space')) {
      iconData = Icons.work_rounded;
    } else if (n.contains('ac') ||
        n.contains('air') ||
        n.contains('cool') ||
        n.contains('snowflake')) {
      iconData = Icons.ac_unit_rounded;
    }

    return Icon(iconData, size: 16, color: color);
  }

  Widget _buildModernTripCard(BuildContext context, Map<String, dynamic> trip) {
    final String priceStr =
        double.tryParse(trip['price'].toString())?.toStringAsFixed(0) ??
        trip['price'].toString();
    final int totalSeats = trip['total_seats'] as int? ?? 40;
    final int bookedCount = (trip['booked_seats'] as List?)?.length ?? 0;
    final int seatsLeft = (totalSeats - bookedCount).clamp(0, totalSeats);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A2540).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Row (Bus Info & Price Pill) ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0A2540,
                            ).withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.directions_bus_rounded,
                            color: Color(0xFF0A2540),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip['bus_name'],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0A2540),
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              trip['reg'],
                              style: TextStyle(
                                fontSize: 10,
                                color: const Color(
                                  0xFF0A2540,
                                ).withValues(alpha: 0.5),
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Rs. $priceStr',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Route Row (Large Bold Dark Blue Text with Arrow) ──
                Row(
                  children: [
                    Text(
                      trip['origin'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0A2540),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.east_rounded,
                      color: Color(0xFF2563EB),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trip['destination'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0A2540),
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Ice-Blue Tags and Amenities Icon Row ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        // Highlighted Time/Date Tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFBFDBFE),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 13,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 4.5),
                              Text(
                                trip['departure'],
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E40AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Seats Left Tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0A2540,
                            ).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.event_seat_rounded,
                                size: 12,
                                color: Color(0xFF0A2540),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$seatsLeft seats left',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF0A2540),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Amenities Icon Only Wrap (monochromatic gray)
                    if (trip['amenities'] != null &&
                        (trip['amenities'] as List).isNotEmpty)
                      Row(
                        children: (trip['amenities'] as List).map<Widget>((
                          ame,
                        ) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 6.0),
                            child: Tooltip(
                              message: ame.toString(),
                              child: _getAmenityIcon(ame.toString()),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // ── Divider & Action Button Block ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
              border: Border(
                top: BorderSide(
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BusDetailsScreen(trip: trip),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2540),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Book Seats',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Seat Selector Screen
class SeatSelectorScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> trip;
  const SeatSelectorScreen({super.key, required this.trip});

  @override
  ConsumerState<SeatSelectorScreen> createState() => _SeatSelectorScreenState();
}

class _SeatSelectorScreenState extends ConsumerState<SeatSelectorScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _isBookingInProgress = false;
  late AnimationController _introController;
  late Animation<double> _perspectiveAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  dynamic _wsChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _perspectiveAnimation = Tween<double>(begin: -0.7, end: 0.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _slideAnimation = Tween<double>(begin: 350.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 1.0, curve: Curves.fastOutSlowIn),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSeats();
      _initRealtimeWebSocket();
      _startSyncTimer();
    });
  }

  Future<void> _initRealtimeWebSocket() async {
    try {
      final tripId = widget.trip['id'].toString();
      final state = ref.read(appStateProvider);
      final wsUri = 'ws://127.0.0.1:8000/api/v1/trips/ws/$tripId';

      _wsChannel = await WebSocket.connect(wsUri);
      _wsChannel?.listen(
        (message) {
          try {
            final data = json.decode(message.toString());
            final event = data['event'];
            final List seats = data['seats'] ?? [];

            if (event == 'SEAT_HELD') {
              for (var s in seats) {
                state.heldSeats.add(s.toString());
              }
              state.notifyListeners();
            } else if (event == 'SEAT_BOOKED') {
              for (var s in seats) {
                state.bookedSeats.add(s.toString());
              }
              state.notifyListeners();
            } else if (event == 'SEAT_RELEASED') {
              for (var s in seats) {
                state.heldSeats.remove(s.toString());
                state.bookedSeats.remove(s.toString());
              }
              state.notifyListeners();
            }
          } catch (e) {
            debugPrint('Error parsing WS message: $e');
          }
        },
        onError: (err) => debugPrint('WebSocket error: $err'),
        onDone: () => debugPrint('WebSocket connection closed.'),
      );
    } catch (e) {
      debugPrint('Real-time WebSocket connection failed: $e');
    }
  }

  void _startSyncTimer() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (mounted && !_isBookingInProgress) {
        final state = ref.read(appStateProvider);
        await state.loadSeatAvailability(widget.trip['id'].toString());
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    try {
      _wsChannel?.close();
    } catch (_) {}
    _introController.dispose();
    super.dispose();
  }

  Future<void> _refreshSeats() async {
    setState(() => _isLoading = true);
    final state = ref.read(appStateProvider);
    state.clearSelectedSeats();
    await state.loadSeatAvailability(widget.trip['id'].toString(), clearFirst: true);
    if (mounted) {
      setState(() => _isLoading = false);
      _introController.reset();
      _introController.forward();
    }
  }

  void _handleConfirmAndBook(
    AppState state,
    Map<String, dynamic> passengerDetails,
  ) async {
    setState(() => _isBookingInProgress = true);

    // 1. Create booking (Pending)
    final booking = await state.initiateBooking(
      widget.trip['id'].toString(),
      passengerDetails,
    );
    if (booking == null) {
      if (mounted) {
        setState(() => _isBookingInProgress = false);
        SeatyNotifications.show(
          context,
          'Failed to hold seats. They may have just been booked.',
          isError: true,
        );
      }
      return;
    }

    // 2. Initiate payment session
    final payment = await state.initiatePayment(booking['id'].toString());
    if (payment == null) {
      if (mounted) {
        setState(() => _isBookingInProgress = false);
        SeatyNotifications.show(
          context,
          'Failed to initiate payment session.',
          isError: true,
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _isBookingInProgress = false);
      // Navigate to sandbox payment screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SandboxPaymentScreen(
            payment: payment,
            trip: widget.trip,
            booking: booking,
          ),
        ),
      );
    }
  }

  void _showPassengerDetailsSheet(BuildContext context, AppState state) {
    final selectedSeats = state.selectedSeats.toList();
    if (selectedSeats.isEmpty) return;

    String bookingFor = 'self'; // 'self' or 'other'

    final nameController = TextEditingController(text: state.userName);
    final phoneController = TextEditingController(text: state.userPhone);
    final nicController = TextEditingController(text: state.userNic);
    String primaryGender =
        state.selectedSeatGenders[selectedSeats.first] ??
        (state.userGender.isEmpty ? 'Male' : state.userGender);

    final Map<String, String> guestGenders = {};
    for (int i = 1; i < selectedSeats.length; i++) {
      final String seat = selectedSeats[i];
      guestGenders[seat] = state.selectedSeatGenders[seat] ?? 'Female';
    }

    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isSelf = bookingFor == 'self';

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      const Text(
                        'Passenger Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Confirm details for your seat: ${selectedSeats.first}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    bookingFor = 'self';
                                    nameController.text = state.userName;
                                    phoneController.text = state.userPhone;
                                    nicController.text = state.userNic;
                                    primaryGender = state.userGender.isEmpty
                                        ? 'Male'
                                        : state.userGender;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelf
                                        ? const Color(0xFF2563EB)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'For Me',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    bookingFor = 'other';
                                    nameController.clear();
                                    phoneController.clear();
                                    nicController.clear();
                                    primaryGender = 'Male';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !isSelf
                                        ? const Color(0xFF2563EB)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'For Others',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      _buildLabel('Passenger Name'),
                      TextFormField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDec(
                          'Enter passenger\'s full name',
                          Icons.person_outline,
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      _buildLabel('Phone Number'),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDec(
                          'Enter phone number',
                          Icons.phone_android_outlined,
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Phone number is required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      _buildLabel('NIC Number'),
                      TextFormField(
                        controller: nicController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDec(
                          'e.g. 199912345678 or 991234567V',
                          Icons.badge_outlined,
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'NIC is required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      _buildLabel('Gender'),
                      DropdownButtonFormField<String>(
                        value: primaryGender,
                        dropdownColor: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: _buildInputDec(
                          'Select Gender',
                          Icons.face_outlined,
                        ),
                        items: ['Male', 'Female']
                            .map(
                              (g) => DropdownMenuItem(
                                value: g,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4.0,
                                  ),
                                  child: Text(
                                    g,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => primaryGender = val);
                          }
                        },
                      ),

                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () {
                            if (!formKey.currentState!.validate()) return;

                            Navigator.pop(context);

                            final Map<String, dynamic> primaryDetails = {
                              'name': nameController.text.trim(),
                              'phone': phoneController.text.trim(),
                              'nic': nicController.text.trim(),
                              'gender': primaryGender,
                              'booking_type': bookingFor,
                            };

                            final List<Map<String, String>> guests = [];
                            guestGenders.forEach((seat, gender) {
                              guests.add({'seat': seat, 'gender': gender});
                            });

                            final Map<String, dynamic> fullDetails = {
                              'primary': primaryDetails,
                              'guests': guests,
                            };

                            _handleConfirmAndBook(state, fullDetails);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Continue to Payment',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _buildInputDec(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.5), size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.trip['bus_name'] ?? 'Select Seats',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              widget.trip['reg'] ?? '',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)),
            )
          : Column(
              children: [
                // Realistic Legend Bar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem(const Color(0xFFFFFFFF), 'Available', border: const Color(0xFFCBD5E1)),
                      _buildLegendItem(const Color(0xFF2563EB), 'Selected'),
                      _buildLegendItem(const Color(0xFF1E3A8A), 'Male'),
                      _buildLegendItem(const Color(0xFFE11D48), 'Female'),
                      _buildLegendItem(const Color(0xFFD97706), 'Held'),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Seat Grid inside Realistic Bus Chassis Canvas
                Builder(
                  builder: (context) {
                    final layout =
                        widget.trip['seat_layout'] ??
                        {'rows': 10, 'columns': 4, 'aisle_after_column': 2};
                    final int rows = layout['rows'] ?? 10;
                    final int columns = layout['columns'] ?? 4;
                    final int aisleAfter = layout['aisle_after_column'] ?? 2;

                    return Expanded(
                      child: Container(
                        width: double.infinity,
                        color: const Color(0xFFF1F5F9),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 480),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(28),
                                  topRight: Radius.circular(28),
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                                border: Border.all(
                                  color: const Color(0xFFCBD5E1),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final double gridHeight = constraints.maxHeight;
                                  final double availableGridHeight = gridHeight - 70.0;
                                  final double rowHeight =
                                      (availableGridHeight / rows).clamp(34.0, 58.0);
                                  final double seatHeight = (rowHeight - 6.0).clamp(28.0, 48.0);
                                  final double seatWidth = (seatHeight * 1.35).clamp(42.0, 58.0);

                                  return Column(
                                    children: [
                                      _buildCabinFront(),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: _buildFlatGrid(
                                          state,
                                          layout,
                                          rows,
                                          columns,
                                          aisleAfter,
                                          seatWidth,
                                          seatHeight,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Bottom Checkout Bar
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A2540),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, -6),
                      ),
                    ],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.selectedSeats.isEmpty
                                    ? 'No seats selected'
                                    : '${state.selectedSeats.length} Seat${state.selectedSeats.length > 1 ? 's' : ''} Selected',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if (state.selectedSeats.isNotEmpty)
                                Text(
                                  state.selectedSeats.join(', '),
                                  style: const TextStyle(
                                    color: Color(0xFFFF8A50),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            'Rs. ${(widget.trip['price'] * state.selectedSeats.length).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFF8A50),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed:
                            (state.selectedSeats.isEmpty || _isBookingInProgress)
                                ? null
                                : () => _showPassengerDetailsSheet(context, state),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF334155),
                          disabledForegroundColor: Colors.white30,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isBookingInProgress
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Confirm & Book Seats',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 18),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCabinFront() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // LEFT SIDE: PASSENGER ENTRY DOOR (Sri Lanka RHD Bus Standard)
          const Row(
            children: [
              Icon(
                Icons.sensor_door_rounded,
                color: Color(0xFF10B981),
                size: 16,
              ),
              SizedBox(width: 4),
              Text(
                'ENTRY DOOR',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // CENTER: WINDSHIELD LINE INDICATOR
          Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // RIGHT SIDE: DRIVER CABIN (Sri Lanka Right-Hand Drive)
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'DRIVER CABIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Steering (RHD)',
                    style: TextStyle(color: Color(0xFFFF8A50), fontSize: 9),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.airline_seat_recline_extra_rounded,
                  color: Color(0xFFFF8A50),
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlatGrid(
    AppState state,
    Map<String, dynamic> layout,
    int rows,
    int columns,
    int aisleAfter,
    double seatWidth,
    double seatHeight,
  ) {
    final List<dynamic>? customSeatsList = layout['seats'];
    final int gridColumns = aisleAfter > 0 ? columns + 1 : columns;

    return Column(
      children: List.generate(rows, (rIndex) {
        int row = rIndex + 1;
        return Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(gridColumns, (cIndex) {
              Map<String, dynamic>? customSeat;
              if (customSeatsList != null) {
                for (var s in customSeatsList) {
                  if (s is Map && s['row'] == row && s['col'] == cIndex) {
                    customSeat = Map<String, dynamic>.from(s);
                    break;
                  }
                }
              }

              if (customSeat == null) {
                if (aisleAfter > 0 && cIndex == aisleAfter) {
                  return SizedBox(
                    width: seatWidth,
                    child: Center(
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        color: const Color(0xFF94A3B8).withValues(alpha: 0.3),
                        size: 14,
                      ),
                    ),
                  );
                }
                if (customSeatsList != null) {
                  return SizedBox(width: seatWidth);
                }
              }

              int seatColIndex = cIndex;
              bool hasAisleInThisRow = aisleAfter > 0 && rIndex < (rows - 1);
              if (hasAisleInThisRow && cIndex > aisleAfter) {
                seatColIndex = cIndex - 1;
              }

              String seatLabel = (customSeat != null && customSeat['label'] != null)
                  ? customSeat['label'].toString()
                  : '${(rIndex * 4) + seatColIndex + 1}';

              bool isSelected = state.selectedSeats.contains(seatLabel);
              bool isBooked = state.bookedSeats.contains(seatLabel);
              bool isHeld = state.heldSeats.contains(seatLabel);

              String gender = '';
              if (isBooked) {
                gender = state.seatGenders[seatLabel]?.toString() ?? '';
              } else if (isSelected) {
                gender = state.selectedSeatGenders[seatLabel]?.toString() ?? '';
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Animated3DSeat(
                  label: seatLabel,
                  isSelected: isSelected,
                  isBooked: isBooked,
                  isHeld: isHeld,
                  gender: gender,
                  width: seatWidth,
                  height: seatHeight,
                  onTap: () {
                    if (isSelected) {
                      state.deselectSeat(seatLabel);
                    } else {
                      _showGenderSelectionDialog(context, state, seatLabel);
                    }
                  },
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  void _showGenderSelectionDialog(
    BuildContext context,
    AppState state,
    String seatLabel,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Select Passenger for Seat $seatLabel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          state.selectSeatWithGender(seatLabel, 'Male');
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1E3A8A,
                            ).withValues(alpha: 0.2),
                            border: Border.all(
                              color: const Color(0xFF1E3A8A),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.face_rounded,
                                color: Color(0xFF60A5FA),
                                size: 36,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Male',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          state.selectSeatWithGender(seatLabel, 'Female');
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFE11D48,
                            ).withValues(alpha: 0.2),
                            border: Border.all(
                              color: const Color(0xFFE11D48),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.face_3_rounded,
                                color: Color(0xFFF472B6),
                                size: 36,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Female',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegendItem(Color color, String label, {Color? border}) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
              color: border ?? Colors.transparent,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

class Animated3DSeat extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isBooked;
  final bool isHeld;
  final String gender;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const Animated3DSeat({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isBooked,
    required this.isHeld,
    required this.gender,
    required this.width,
    required this.height,
    this.onTap,
  });

  @override
  State<Animated3DSeat> createState() => _Animated3DSeatState();
}

class _Animated3DSeatState extends State<Animated3DSeat>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.15),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant Animated3DSeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Gradient fillGradient;
    Color borderColor;
    Color textColor;
    IconData? genderIcon;

    if (widget.isSelected) {
      if (widget.gender.toLowerCase() == 'male') {
        fillGradient = const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF1E3A8A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
        borderColor = const Color(0xFF60A5FA);
        textColor = Colors.white;
        genderIcon = Icons.man_rounded;
      } else if (widget.gender.toLowerCase() == 'female') {
        fillGradient = const LinearGradient(
          colors: [Color(0xFFF43F5E), Color(0xFFBE123C)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
        borderColor = const Color(0xFFFB7185);
        textColor = Colors.white;
        genderIcon = Icons.woman_rounded;
      } else {
        fillGradient = const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
        borderColor = const Color(0xFF93C5FD);
        textColor = Colors.white;
      }
    } else if (widget.isBooked) {
      if (widget.gender.toLowerCase() == 'male') {
        fillGradient = const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
        borderColor = const Color(0xFF2563EB).withValues(alpha: 0.4);
        textColor = Colors.white.withValues(alpha: 0.6);
        genderIcon = Icons.man_rounded;
      } else if (widget.gender.toLowerCase() == 'female') {
        fillGradient = const LinearGradient(
          colors: [Color(0xFFBE123C), Color(0xFF881337)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
        borderColor = const Color(0xFFE11D48).withValues(alpha: 0.4);
        textColor = Colors.white.withValues(alpha: 0.6);
        genderIcon = Icons.woman_rounded;
      } else {
        fillGradient = const LinearGradient(
          colors: [Color(0xFF475569), Color(0xFF334155)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
        borderColor = const Color(0xFF475569).withValues(alpha: 0.4);
        textColor = Colors.white.withValues(alpha: 0.5);
      }
    } else if (widget.isHeld) {
      fillGradient = const LinearGradient(
        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
      borderColor = const Color(0xFFFFB020);
      textColor = Colors.white;
    } else {
      fillGradient = const LinearGradient(
        colors: [Colors.white, Color(0xFFF8FAFC)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
      borderColor = const Color(0xFFCBD5E1);
      textColor = const Color(0xFF0F172A);
    }

    final bool isSpecialState = widget.isSelected || widget.isBooked || widget.isHeld;

    return GestureDetector(
      onTap: (widget.isBooked || widget.isHeld) ? null : widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                gradient: fillGradient,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                  width: widget.isSelected ? 2.0 : 1.2,
                ),
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: borderColor.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Stack(
                children: [
                  // Upper headrest cushion indicator (real seat look)
                  Positioned(
                    top: 3,
                    left: 5,
                    right: 5,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: isSpecialState
                            ? Colors.white.withValues(alpha: 0.18)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // Seat bottom cushion crease / design line
                  Positioned(
                    bottom: 4,
                    left: 4,
                    right: 4,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: isSpecialState
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  // Armrests (Wing/support armrest indicator lines)
                  Positioned(
                    top: 6,
                    bottom: 6,
                    left: 2,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: isSpecialState
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    bottom: 6,
                    right: 2,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: isSpecialState
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  // Seat Label
                  Center(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: (widget.height * 0.28).clamp(9.0, 13.0),
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  // Gender Icon Badge
                  if (genderIcon != null)
                    Positioned(
                      top: 2,
                      right: 3,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          genderIcon,
                          size: 9,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ConductorTripDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> trip;
  const ConductorTripDetailsScreen({super.key, required this.trip});

  @override
  ConsumerState<ConductorTripDetailsScreen> createState() =>
      _ConductorTripDetailsScreenState();
}

class _ConductorTripDetailsScreenState
    extends ConsumerState<ConductorTripDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _manifestData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    ref.read(appStateProvider).stopStreamingGPS();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final state = ref.read(appStateProvider);
    await state.loadSeatAvailability(widget.trip['id'].toString(), clearFirst: true);
    final manifest = await state.fetchTripManifest(
      widget.trip['id'].toString(),
    );
    if (mounted) {
      setState(() {
        _manifestData = manifest;
        _isLoading = false;
      });
      _checkAndStartGpsStreaming(state);
    }
  }

  Future<void> _checkAndStartGpsStreaming(AppState state) async {
    final departureStr = widget.trip['departure'];
    final arrivalStr = widget.trip['arrival'];
    final vehicleId = widget.trip['vehicle_id']?.toString() ?? '';

    if (departureStr == null || vehicleId.isEmpty) return;

    try {
      final departureTime = DateTime.parse(departureStr.replaceAll(' ', 'T'));
      final now = DateTime.now();
      final startTime = departureTime.subtract(const Duration(minutes: 30));

      final arrivalTime = (arrivalStr != null && arrivalStr.toString().isNotEmpty)
          ? DateTime.parse(arrivalStr.toString().replaceAll(' ', 'T'))
          : departureTime.add(const Duration(hours: 4)); // Fallback duration

      if (now.isAfter(startTime) && now.isBefore(arrivalTime)) {
        if (!state.isStreamingGPS) {
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
          LocationPermission permission = await Geolocator.checkPermission();

          if (!serviceEnabled || permission == LocationPermission.denied) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF0A2540),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    'GPS Broadcast Required',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  content: const Text(
                    'Live tracking is now active for this ride. Please enable GPS so passengers can view your bus in real-time.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Later', style: TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await state.startStreamingGPS(vehicleId, true);
                        if (mounted) {
                          SeatyNotifications.show(
                            context,
                            'GPS Tracking Started Successfully',
                          );
                        }
                      },
                      child: const Text('Start Broadcast'),
                    ),
                  ],
                ),
              );
            }
          } else {
            await state.startStreamingGPS(vehicleId, true);
            if (mounted) {
              SeatyNotifications.show(
                context,
                'GPS Location Broadcast Started Automatically',
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error starting GPS stream in conductor trip: $e');
    }
  }

  String _formatRemainingTime(int totalMinutes) {
    if (totalMinutes < 0) return '0m';
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return '${hours}h ${mins}m';
    }
    return '${totalMinutes}m';
  }

  void _showPassengerDetails(
    Map<String, dynamic> passenger,
    AppState state,
    List<String> boardedSeats,
  ) {
    bool isBoarded = boardedSeats.contains(passenger['seat']);

    final departureStr = widget.trip['departure'];
    bool isBoardingAvailable = true;
    String disabledReason = "";
    if (departureStr != null) {
      try {
        final departureTime = DateTime.parse(departureStr.replaceAll(' ', 'T'));
        final now = DateTime.now();
        final difference = departureTime.difference(now);
        if (difference.inMinutes > 30) {
          isBoardingAvailable = false;
          disabledReason = "Boarding opens 30 minutes before departure. Departure is in ${_formatRemainingTime(difference.inMinutes)} (at $departureStr).";
        }
      } catch (e) {
        debugPrint('Error parsing departure time: $e');
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2540),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Seat ${passenger['seat']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('Name', passenger['name']),
                        _buildDetailRow(
                          'Gender',
                          passenger['gender'].toString().toUpperCase(),
                        ),
                        _buildDetailRow(
                          'Phone',
                          passenger['phone'].toString().isEmpty
                              ? 'N/A'
                              : passenger['phone'],
                        ),
                        _buildDetailRow(
                          'Booking ID',
                          passenger['booking_id'].toString().substring(0, 8) +
                              '...',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: (isBoarded || isBoardingAvailable)
                        ? () async {
                            try {
                              final updatedBoarded = await state.toggleBoarding(
                                widget.trip['id'].toString(),
                                passenger['seat'],
                              );
                              if (updatedBoarded != null) {
                                setState(() {
                                  _manifestData!['boarded_seats'] = updatedBoarded;
                                });
                                setModalState(() {
                                  isBoarded = updatedBoarded.contains(
                                    passenger['seat'],
                                  );
                                });
                                if (mounted) Navigator.pop(context);
                                SeatyNotifications.show(
                                  context,
                                  isBoarded
                                      ? 'Passenger Marked as Boarded'
                                      : 'Boarding Undone',
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                Navigator.pop(context);
                                final errorMsg = e.toString().replaceFirst('Exception: ', '');
                                SeatyNotifications.show(
                                  context,
                                  errorMsg,
                                  isError: true,
                                );
                              }
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBoarded
                          ? Colors.red.shade400
                          : isBoardingAvailable
                              ? const Color(0xFF2E7D32)
                              : Colors.grey,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isBoarded
                          ? 'Undo Boarding'
                          : isBoardingAvailable
                              ? 'Mark as Boarded'
                              : 'Boarding Locked',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!isBoarded && !isBoardingAvailable) ...[
                    const SizedBox(height: 12),
                    Text(
                      disabledReason,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red.shade200,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final layout =
        widget.trip['seat_layout'] ??
        {'rows': 10, 'columns': 4, 'aisle_after_column': 2};
    final int rows = layout['rows'] ?? 10;
    final int columns = layout['columns'] ?? 4;
    final int aisleAfter = layout['aisle_after_column'] ?? 2;
    final int gridColumns = aisleAfter > 0 ? columns + 1 : columns;
    final int totalGridItems = rows * gridColumns;
    final List<dynamic>? customSeatsList = layout['seats'];

    List<String> boardedSeats = _manifestData != null
        ? List<String>.from(_manifestData!['boarded_seats'] ?? [])
        : [];
    List<dynamic> manifestList = _manifestData != null
        ? _manifestData!['manifest'] ?? []
        : [];

    int totalBooked = state.bookedSeats.length;
    int totalBoarded = boardedSeats.length;
    int capacity = widget.trip['total_seats'] ?? 40;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                state.isStreamingGPS ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                color: state.isStreamingGPS ? const Color(0xFF10B981) : Colors.black38,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                state.isStreamingGPS ? 'LIVE ON' : 'LIVE OFF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: state.isStreamingGPS ? const Color(0xFF10B981) : Colors.black38,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: state.isStreamingGPS,
                activeColor: const Color(0xFF10B981),
                activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.black12,
                onChanged: (bool value) async {
                  final vehicleId = widget.trip['vehicle_id']?.toString() ?? '';
                  if (vehicleId.isEmpty) return;

                  if (value) {
                    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                    LocationPermission permission = await Geolocator.checkPermission();

                    if (!serviceEnabled || permission == LocationPermission.denied) {
                      _checkAndStartGpsStreaming(state);
                    } else {
                      await state.startStreamingGPS(vehicleId, true);
                    }
                  } else {
                    state.stopStreamingGPS();
                  }
                },
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)),
            )
          : Column(
              children: [
                // Summary Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF0A2540),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat('Capacity', capacity.toString(), Colors.white),
                      _buildStat(
                        'Booked',
                        totalBooked.toString(),
                        Colors.blue.shade200,
                      ),
                      _buildStat(
                        'Boarded',
                        totalBoarded.toString(),
                        Colors.green.shade400,
                      ),
                    ],
                  ),
                ),

                // Legend
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem(
                        const Color(0xFFF4F6F9),
                        'Empty',
                        border: Colors.black12,
                      ),
                      _buildLegendItem(const Color(0xFF0F2C59), 'Male'),
                      _buildLegendItem(const Color(0xFFF472B6), 'Female'),
                      _buildLegendItem(const Color(0xFF2E7D32), 'Boarded'),
                    ],
                  ),
                ),

                // Bus Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(28),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridColumns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: totalGridItems,
                    itemBuilder: (context, index) {
                      int colIndex = index % gridColumns;
                      int row = index ~/ gridColumns + 1;

                      Map<String, dynamic>? customSeat;
                      if (customSeatsList != null) {
                        for (var s in customSeatsList) {
                          if (s is Map &&
                              s['row'] == row &&
                              s['col'] == colIndex) {
                            customSeat = Map<String, dynamic>.from(s);
                            break;
                          }
                        }
                        if (customSeat == null) {
                          if (aisleAfter > 0 && colIndex == aisleAfter) {
                            return const Center(
                              child: Icon(
                                Icons.unfold_more,
                                color: Colors.black12,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                      } else {
                        if (aisleAfter > 0 && colIndex == aisleAfter) {
                          return const Center(
                            child: Icon(
                              Icons.unfold_more,
                              color: Colors.black12,
                            ),
                          );
                        }
                      }

                      int seatColIndex = colIndex;
                      if (customSeat == null &&
                          aisleAfter > 0 &&
                          colIndex > aisleAfter) {
                        seatColIndex = colIndex - 1;
                      }
                      String seatLabel = customSeat != null
                          ? customSeat['label']
                          : '${(row - 1) * columns + (aisleAfter > 0 && colIndex > aisleAfter ? colIndex - 1 : colIndex) + 1}';

                      bool isBooked = state.bookedSeats.contains(seatLabel);
                      bool isBoarded = boardedSeats.contains(seatLabel);

                      Color seatColor = const Color(0xFFF4F6F9);
                      Color textColor = const Color(0xFF0A2540);
                      Color borderColor = Colors.black12;

                      if (isBoarded) {
                        seatColor = const Color(0xFF2E7D32);
                        textColor = Colors.white;
                        borderColor = const Color(0xFF2E7D32);
                      } else if (isBooked) {
                        final gender =
                            state.seatGenders[seatLabel]?.toLowerCase() ?? '';
                        if (gender == 'male') {
                          seatColor = const Color(0xFF0F2C59);
                          textColor = Colors.white;
                          borderColor = const Color(0xFF0F2C59);
                        } else if (gender == 'female') {
                          seatColor = const Color(0xFFF472B6);
                          textColor = Colors.white;
                          borderColor = const Color(0xFFF472B6);
                        } else {
                          seatColor = Colors.grey.shade400;
                          textColor = Colors.white;
                          borderColor = Colors.grey.shade500;
                        }
                      }

                      return InkWell(
                        onTap: isBooked
                            ? () {
                                // Find passenger in manifest
                                final passenger = manifestList.firstWhere(
                                  (p) => p['seat'] == seatLabel,
                                  orElse: () => <String, dynamic>{},
                                );
                                if (passenger.isNotEmpty) {
                                  _showPassengerDetails(
                                    passenger,
                                    state,
                                    boardedSeats,
                                  );
                                } else {
                                  SeatyNotifications.show(
                                    context,
                                    'Passenger details not found in manifest.',
                                  );
                                }
                              }
                            : null,
                        child: Container(
                          decoration: BoxDecoration(
                            color: seatColor,
                            border: Border.all(color: borderColor, width: 1.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            seatLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label, {Color? border}) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: border ?? Colors.transparent),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

// Custom Premium Sandbox Payment Screen
class SandboxPaymentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> payment;
  final Map<String, dynamic> booking;
  final Map<String, dynamic> trip;

  const SandboxPaymentScreen({
    super.key,
    required this.payment,
    required this.booking,
    required this.trip,
  });

  @override
  ConsumerState<SandboxPaymentScreen> createState() =>
      _SandboxPaymentScreenState();
}

class _SandboxPaymentScreenState extends ConsumerState<SandboxPaymentScreen> {
  late Timer _timer;
  int _secondsRemaining = 600; // 10 minutes hold timer
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timer.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    SeatyNotifications.show(
      context,
      'Seat hold expired. Please try booking again.',
      isError: true,
    );
    Navigator.pop(context);
  }

  Future<void> _processPayment(bool success) async {
    setState(() => _isProcessing = true);
    final state = ref.read(appStateProvider);
    final transactionId = widget.payment['gateway_transaction_id'];

    final bool result = success
        ? await state.completeSandboxPayment(transactionId)
        : await state.failSandboxPayment(transactionId);

    if (mounted) {
      setState(() => _isProcessing = false);
      if (result) {
        SeatyNotifications.show(
          context,
          success ? 'Payment Completed Successfully!' : 'Booking cancelled.',
          isError: !success,
          isWarning: !success,
        );
        Navigator.pop(context);
      } else {
        SeatyNotifications.show(
          context,
          'Something went wrong communicating with sandbox server.',
          isError: true,
        );
      }
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatTimer() {
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final selectedSeatsList = List<String>.from(
      widget.booking['selected_seats'] ?? [],
    );
    final double fare =
        double.tryParse(widget.booking['total_price'].toString()) ?? 0.0;
    final double platformFee =
        double.tryParse(widget.payment['platform_fee'].toString()) ?? 25.0;
    final double total =
        double.tryParse(widget.payment['amount'].toString()) ??
        (fare + platformFee);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Seaty Checkout'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hold Timer Capsule
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade200),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.hourglass_bottom_rounded,
                        color: Colors.amber.shade800,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Seats held for ${_formatTimer()}',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Order Details Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.black12),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Booking Summary',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Color(0xFF0A2540),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildRow('Bus Service', widget.trip['bus_name']),
                        _buildRow(
                          'Route',
                          '${widget.trip['origin']} → ${widget.trip['destination']}',
                        ),
                        _buildRow(
                          'Selected Seats',
                          selectedSeatsList.join(', '),
                        ),
                        const Divider(height: 24),
                        _buildRow(
                          'Seat Fare',
                          'Rs. ${fare.toStringAsFixed(0)}',
                        ),
                        _buildRow(
                          'Platform Fee',
                          'Rs. ${platformFee.toStringAsFixed(0)}',
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF0A2540),
                              ),
                            ),
                            Text(
                              'Rs. ${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Sandbox Gateway Action Area
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.security,
                        color: Color(0xFF10B981),
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Secure Sandbox Payment Portal',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'This simulates secure token validation. Click authorize to complete reservation.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(height: 24),
                      if (_isProcessing)
                        const CircularProgressIndicator(
                          color: Color(0xFF2563EB),
                        )
                      else ...[
                        ElevatedButton(
                          onPressed: () => _processPayment(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Authorize & Complete Payment',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => _processPayment(false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                          child: const Text(
                            'Cancel & Release Seats',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0A2540),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Owner Main Screen is imported from lib/screens/owner/owner_main_screen.dart

// Owner Ticket Verification Tab
class OwnerScannerTab extends ConsumerStatefulWidget {
  const OwnerScannerTab({super.key});

  @override
  ConsumerState<OwnerScannerTab> createState() => _OwnerScannerTabState();
}

class _OwnerScannerTabState extends ConsumerState<OwnerScannerTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  String? _selectedBookingId;
  Map<String, dynamic>? _scannedTicket;
  bool _scanAttempted = false;
  bool _isCheckingIn = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _simulateScan(List<Map<String, dynamic>> bookings) {
    if (_selectedBookingId == null) return;

    setState(() {
      _scanAttempted = false;
      _scannedTicket = null;
    });

    // Simulate scanning delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final match = bookings.firstWhere(
        (b) => b['id'].toString() == _selectedBookingId,
      );
      setState(() {
        _scanAttempted = true;
        _scannedTicket = match;
      });
    });
  }

  Future<void> _completeCheckIn(AppState state) async {
    if (_scannedTicket == null) return;
    setState(() => _isCheckingIn = true);

    final tripId = _scannedTicket!['trip_id'].toString();
    final seats = List<String>.from(_scannedTicket!['seats'] ?? []);
    List<String> currentBoarded = List<String>.from(
      _scannedTicket!['boarded_seats'] ?? [],
    );

    for (var seat in seats) {
      if (!currentBoarded.contains(seat)) {
        final updated = await state.toggleBoarding(tripId, seat);
        if (updated != null) {
          currentBoarded = updated;
        }
      }
    }

    await state.loadBookings();

    if (mounted) {
      setState(() {
        _scannedTicket!['boarded_seats'] = currentBoarded;
        _isCheckingIn = false;
      });
      SeatyNotifications.show(context, 'Ticket completely checked in!');
    }
  }

  bool _isCheckInAvailable(Map<String, dynamic> ticket) {
    try {
      final departureStr = ticket['departure']; // e.g. "2026-07-13 14:00"
      if (departureStr == null) return false;
      final departureTime = DateTime.parse(departureStr.replaceAll(' ', 'T'));
      final now = DateTime.now();

      final difference = departureTime.difference(now);

      // Check-in becomes available if departure is 30 mins or less from now, OR has already started
      return difference.inMinutes <= 30;
    } catch (e) {
      debugPrint('Error parsing departure time: $e');
      return false;
    }
  }

  void _openCameraScanOverlay(AppState state) {
    final ownerBookings = state.bookings;
    if (ownerBookings.isEmpty) {
      SeatyNotifications.show(
        context,
        'No active passenger bookings to scan.',
        isError: true,
      );
      return;
    }

    final TextEditingController qrInputController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.76,
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Live QR Scanner Feed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Point camera at passenger ticket QR code',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),

                // Live Finder square
                Expanded(
                  child: Center(
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF2563EB),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: MobileScanner(
                              onDetect: (capture) {
                                final List<Barcode> barcodes = capture.barcodes;
                                if (barcodes.isNotEmpty) {
                                  final barcodeValue = barcodes.first.rawValue;
                                  if (barcodeValue != null &&
                                      barcodeValue.isNotEmpty) {
                                    Navigator.pop(
                                      context,
                                    ); // Close scanning overlay

                                    // Validate if it belongs to ownerBookings
                                    String? actualMatchedId;
                                    for (var b in ownerBookings) {
                                      if (b['id'].toString().toLowerCase() ==
                                          barcodeValue.toLowerCase()) {
                                        actualMatchedId = b['id'].toString();
                                        break;
                                      }
                                    }

                                    if (actualMatchedId != null) {
                                      setState(() {
                                        _selectedBookingId = actualMatchedId;
                                        _scanAttempted = false;
                                      });
                                      _simulateScan(
                                        ownerBookings,
                                      ); // It will load ticket detail
                                    } else {
                                      setState(() {
                                        _selectedBookingId = null;
                                        _scannedTicket = null;
                                        _scanAttempted = true;
                                      });
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                          // Scanner pulsing line
                          AnimatedBuilder(
                            animation: _animController,
                            builder: (context, child) {
                              final double dy =
                                  (_animController.value * 200) - 100;
                              return Positioned(
                                top: 100 + dy,
                                child: Container(
                                  width: 200,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.redAccent.withOpacity(
                                          0.8,
                                        ),
                                        blurRadius: 10,
                                        spreadRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const Positioned(
                            bottom: 12,
                            child: Text(
                              'Align QR within box',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Simulator control input in scanner view
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'SIMULATOR QR CODE INPUT',
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: qrInputController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter Ticket ID (e.g. AFB4ED81)',
                          hintStyle: const TextStyle(
                            color: Colors.white30,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.qr_code_2_rounded,
                            color: Colors.white70,
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          final input = qrInputController.text
                              .trim()
                              .toLowerCase();
                          if (input.isEmpty) {
                            SeatyNotifications.show(
                              context,
                              'Please enter a ticket ID to scan.',
                              isError: true,
                            );
                            return;
                          }

                          // Search for the ticket
                          String? matchedId;
                          for (var b in ownerBookings) {
                            final bId = b['id'].toString().toLowerCase();
                            final passengerName = (b['passenger_name'] ?? '')
                                .toString()
                                .toLowerCase();
                            if (bId.contains(input) ||
                                passengerName.contains(input)) {
                              matchedId = b['id'].toString();
                              break;
                            }
                          }

                          Navigator.pop(context); // Close scanning overlay

                          if (matchedId != null) {
                            setState(() {
                              _selectedBookingId = matchedId;
                              _scanAttempted = false;
                            });
                            _simulateScan(ownerBookings);
                          } else {
                            // If no match found, trigger scan failure state
                            setState(() {
                              _selectedBookingId = null;
                              _scannedTicket = null;
                              _scanAttempted = true;
                            });
                          }
                        },
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text(
                          'Simulate QR Code Detection',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final ownerBookings = state.bookings;

    if (ownerBookings.isNotEmpty && _selectedBookingId == null) {
      _selectedBookingId = ownerBookings[0]['id'].toString();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 100.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ticket Scanner Console',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0A2540),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Scan passenger QR tickets to verify boarding authorization.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // 1. Scan Trigger Button (Interactive & Clean)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 42,
                      icon: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Color(0xFF2563EB),
                      ),
                      onPressed: () => _openCameraScanOverlay(state),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _openCameraScanOverlay(state),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A2540),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Start QR Code Scan',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(),
          const SizedBox(height: 16),

          // 2. Verification Output
          if (_scanAttempted && _scannedTicket != null) ...[
            Builder(
              builder: (context) {
                final tripBoarded = List<String>.from(
                  _scannedTicket!['boarded_seats'] ?? [],
                );
                final tktSeats = List<String>.from(
                  _scannedTicket!['seats'] ?? [],
                );
                final bool isFullyBoarded =
                    tktSeats.isNotEmpty &&
                    tktSeats.every((s) => tripBoarded.contains(s));

                if (isFullyBoarded) {
                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      border: Border.all(color: const Color(0xFFE57373)),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFFC62828),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'TICKET ALREADY USED',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFC62828),
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'This ticket was already checked in. It cannot be used for boarding again.',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTicketDetailRow(
                          'Passenger',
                          _scannedTicket!['passenger_name'],
                        ),
                        _buildTicketDetailRow(
                          'Seats',
                          _scannedTicket!['seats'].join(', '),
                        ),
                        _buildTicketDetailRow(
                          'Route',
                          '${_scannedTicket!['origin']} ➔ ${_scannedTicket!['destination']}',
                        ),
                        _buildPassengerManifestDetails(_scannedTicket!),
                      ],
                    ),
                  );
                }

                // Otherwise, normal validation
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    border: Border.all(color: const Color(0xFF81C784)),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'TICKET VALIDATED',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildTicketDetailRow(
                        'Passenger',
                        _scannedTicket!['passenger_name'],
                      ),
                      _buildTicketDetailRow(
                        'Seats',
                        _scannedTicket!['seats'].join(', '),
                      ),
                      _buildTicketDetailRow(
                        'Route',
                        '${_scannedTicket!['origin']} ➔ ${_scannedTicket!['destination']}',
                      ),
                      _buildTicketDetailRow(
                        'Fare Status',
                        'PAID (Rs. ${_scannedTicket!['price']})',
                        isPrice: true,
                      ),
                      _buildPassengerManifestDetails(_scannedTicket!),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (context) {
                          // Check if Check-In is active (within 30 minutes of departure)
                          final bool allowed = _isCheckInAvailable(
                            _scannedTicket!,
                          );
                          if (!allowed) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    color: Color(0xFFB7791F),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Check-in is only available starting 30 minutes prior to departure.',
                                      style: TextStyle(
                                        color: Colors.amber.shade900,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ElevatedButton(
                            onPressed: _isCheckingIn
                                ? null
                                : () => _completeCheckIn(state),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isCheckingIn
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Complete Check-In',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ] else if (_scanAttempted) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                border: Border.all(color: const Color(0xFFE57373)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFC62828),
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'INVALID TICKET',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFC62828),
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Scanned QR code is expired, invalid, or unpaid.',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2, color: Colors.grey, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Waiting to scan ticket QR code...',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPassengerManifestDetails(Map<String, dynamic> ticket) {
    final details = ticket['passenger_details'] ?? {};
    final primary = details['primary'] ?? {};
    final guests = details['guests'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(color: Colors.black12, height: 1),
        const SizedBox(height: 14),
        const Row(
          children: [
            Icon(Icons.people_alt_outlined, size: 18, color: Color(0xFF0A2540)),
            SizedBox(width: 8),
            Text(
              'Passenger Manifest Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF0A2540),
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Primary passenger details card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withOpacity(0.04)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2540).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Seat ${ticket['seats'].isNotEmpty ? ticket['seats'][0] : "N/A"}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0A2540),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Primary Booker',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildTicketDetailRow(
                'Name',
                primary['name'] ?? ticket['passenger_name'],
              ),
              _buildTicketDetailRow('Phone', primary['phone'] ?? 'N/A'),
              _buildTicketDetailRow('NIC', primary['nic'] ?? 'N/A'),
              _buildTicketDetailRow('Gender', primary['gender'] ?? 'N/A'),
            ],
          ),
        ),

        // Co-passengers / guests list
        if (guests is List && guests.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Co-Passengers',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          ...guests.map((g) {
            final seatNum = g['seat'] ?? 'N/A';
            final gender = g['gender'] ?? 'N/A';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withOpacity(0.04)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Seat $seatNum',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2563EB),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        g['name'] ?? 'Passenger $seatNum',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: gender.toString().toLowerCase() == 'female'
                          ? Colors.pink.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      gender.toString().toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: gender.toString().toLowerCase() == 'female'
                            ? Colors.pink.shade700
                            : Colors.blue.shade700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildTicketDetailRow(
    String label,
    String value, {
    bool isPrice = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPrice ? const Color(0xFF2563EB) : Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Owner Tab 1: Vehicles List & Registration
class OwnerVehiclesTab extends ConsumerStatefulWidget {
  const OwnerVehiclesTab({super.key});

  @override
  ConsumerState<OwnerVehiclesTab> createState() => _OwnerVehiclesTabState();
}

class _OwnerVehiclesTabState extends ConsumerState<OwnerVehiclesTab> {
  final _nameController = TextEditingController();
  final _regController = TextEditingController();
  int _capacity = 40;

  void _showAddVehicleDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Register Luxury Vehicle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Vehicle Name (e.g. Galle Superliner)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _regController,
                decoration: const InputDecoration(
                  labelText: 'Registration Plate (e.g. WP-ND-1234)',
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Seat Capacity',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _capacity,
                dropdownColor: const Color(0xFF0F172A),
                iconEnabledColor: Colors.white,
                borderRadius: BorderRadius.circular(16),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Select Seat Capacity',
                  hintStyle: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0A2540),
                  prefixIcon: const Icon(
                    Icons.event_seat_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: [24, 36, 40, 42, 54].map((c) {
                  return DropdownMenuItem<int>(
                    value: c,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        '$c Seats',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _capacity = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_nameController.text.isNotEmpty &&
                    _regController.text.isNotEmpty) {
                  ref
                      .read(appStateProvider)
                      .registerVehicle(
                        _nameController.text,
                        _regController.text,
                        _capacity,
                      );
                  _nameController.clear();
                  _regController.clear();
                  Navigator.pop(context);
                }
              },
              child: const Text('Register'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Fleet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _showAddVehicleDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Bus'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: state.vehicles.length,
              itemBuilder: (context, index) {
                final v = state.vehicles[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(
                      Icons.airport_shuttle_rounded,
                      size: 36,
                      color: Color(0xFF2563EB),
                    ),
                    title: Text(v['name']),
                    subtitle: Text('${v['reg']} • ${v['total_seats']} Seats'),
                    trailing: Chip(
                      label: Text(
                        v['is_verified'] ? 'Verified' : 'Pending Approval',
                      ),
                      backgroundColor: v['is_verified']
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      labelStyle: TextStyle(
                        color: v['is_verified'] ? Colors.green : Colors.orange,
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Owner Tab 2: Trip scheduling
class OwnerTripsTab extends ConsumerStatefulWidget {
  const OwnerTripsTab({super.key});

  @override
  ConsumerState<OwnerTripsTab> createState() => _OwnerTripsTabState();
}

class _OwnerTripsTabState extends ConsumerState<OwnerTripsTab> {
  final _priceController = TextEditingController();
  final _timeController = TextEditingController(text: '14:00'); // Default time
  String? _selectedVehicleId;
  String? _selectedRouteId;
  List<dynamic> _routesList = [];
  bool _isLoadingRoutes = false;

  @override
  void initState() {
    super.initState();
    _fetchRouteTemplates();
  }

  Future<void> _fetchRouteTemplates() async {
    setState(() => _isLoadingRoutes = true);
    final state = ref.read(appStateProvider);
    try {
      final response = await http
          .get(Uri.parse('${state.apiBaseUrl}/routes'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _routesList = json.decode(response.body);
            if (_routesList.isNotEmpty) {
              _selectedRouteId = _routesList[0]['id'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading route templates in owner view: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingRoutes = false);
      }
    }
  }

  void _showAddTripDialog() {
    final state = ref.read(appStateProvider);
    if (state.vehicles.isEmpty) {
      SeatyNotifications.show(
        context,
        'Please register a vehicle first.',
        isError: true,
      );
      return;
    }

    _selectedVehicleId = state.vehicles[0]['id'];

    // Set default price based on selected route if available
    if (_routesList.isNotEmpty && _selectedRouteId == null) {
      _selectedRouteId = _routesList[0]['id'];
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Schedule Luxury Trip'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select Vehicle',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedVehicleId,
                      dropdownColor: const Color(0xFF0F172A),
                      iconEnabledColor: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Select Vehicle',
                        hintStyle: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0A2540),
                        prefixIcon: const Icon(
                          Icons.airport_shuttle_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items: state.vehicles.map((v) {
                        return DropdownMenuItem<String>(
                          value: v['id'],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(
                              '${v['name']} (${v['reg']})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setDialogState(() => _selectedVehicleId = val),
                    ),
                    const SizedBox(height: 12),

                    _isLoadingRoutes
                        ? const Center(child: CircularProgressIndicator())
                        : _routesList.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'No pre-defined routes found. Contact administrator.',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select Route Template',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                value: _selectedRouteId,
                                dropdownColor: const Color(0xFF0F172A),
                                iconEnabledColor: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Select Route Template',
                                  hintStyle: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0A2540),
                                  prefixIcon: const Icon(
                                    Icons.route_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                items: _routesList.map((r) {
                                  final stopsCount =
                                      (r['stops'] as List?)?.length ?? 0;
                                  final stopsText = stopsCount > 0
                                      ? ' ($stopsCount stops)'
                                      : ' (direct)';
                                  return DropdownMenuItem<String>(
                                    value: r['id'],
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4.0,
                                      ),
                                      child: Text(
                                        '${r['origin']} ➔ ${r['destination']}$stopsText',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setDialogState(
                                  () => _selectedRouteId = val,
                                ),
                              ),
                            ],
                          ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _timeController,
                      decoration: const InputDecoration(
                        labelText: 'Departure Time (HH:MM)',
                        hintText: 'e.g. 14:30',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Price per Seat (Rs.)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      (_selectedRouteId == null ||
                          _priceController.text.isEmpty)
                      ? null
                      : () {
                          final selectedRoute = _routesList.firstWhere(
                            (r) => r['id'] == _selectedRouteId,
                          );

                          // Format timing: YYYY-MM-DD HH:MM
                          final departureDateTime =
                              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')} ${_timeController.text}';

                          state.scheduleTrip(
                            _selectedVehicleId!,
                            selectedRoute['origin'],
                            selectedRoute['destination'],
                            departureDateTime,
                            double.parse(_priceController.text),
                          );
                          _priceController.clear();
                          Navigator.pop(context);
                          SeatyNotifications.show(
                            context,
                            'Trip scheduled successfully!',
                          );
                        },
                  child: const Text('Schedule'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Scheduled Journeys',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (state.role == 'owner')
                ElevatedButton.icon(
                  onPressed: _showAddTripDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Schedule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await state.loadTrips();
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 110),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: state.trips.length,
                itemBuilder: (context, index) {
                  final trip = state.trips[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ConductorTripDetailsScreen(trip: trip),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${trip['origin']} \u2192 ${trip['destination']}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0A2540),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF2563EB,
                                    ).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    trip['departure'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF4F6F9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.airport_shuttle_rounded,
                                    size: 20,
                                    color: Color(0xFF0A2540),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${trip['bus_name']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        '${trip['reg']} • ${trip['total_seats']} Seats',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Rs. ${trip['price']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Owner Tab 3: GPS Streaming Sender controls
class OwnerStreamingTab extends ConsumerStatefulWidget {
  const OwnerStreamingTab({super.key});

  @override
  ConsumerState<OwnerStreamingTab> createState() => _OwnerStreamingTabState();
}

class _OwnerStreamingTabState extends ConsumerState<OwnerStreamingTab> {
  String? _selectedVehicleId;
  final bool _simulateGps = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        left: 24.0,
        right: 24.0,
        top: 24.0,
        bottom: 110.0,
      ),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live GPS Broadcaster',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Transmit coordinates to passengers tracking your vehicle.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          const Text(
            'Select active vehicle to stream GPS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedVehicleId,
            dropdownColor: const Color(0xFF0F172A),
            iconEnabledColor: Colors.white,
            borderRadius: BorderRadius.circular(16),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Select active vehicle to stream GPS',
              hintStyle: const TextStyle(color: Colors.white60, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF0A2540),
              prefixIcon: const Icon(
                Icons.sensors_rounded,
                color: Colors.white70,
                size: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: state.vehicles.map((v) {
              return DropdownMenuItem<String>(
                value: v['reg'],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    '${v['name']} (${v['reg']})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedVehicleId = val),
          ),
          const SizedBox(height: 32),
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F9),
                border: Border.all(
                  color: state.isStreamingGPS
                      ? const Color(0xFF2563EB).withOpacity(0.5)
                      : Colors.black12,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    state.isStreamingGPS
                        ? Icons.sensors
                        : Icons.sensors_off_rounded,
                    size: 64,
                    color: state.isStreamingGPS
                        ? const Color(0xFF2563EB)
                        : Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.isStreamingGPS
                        ? 'Broadcasting Coordinates...'
                        : 'GPS Stream Idle',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _selectedVehicleId == null
                        ? null
                        : () {
                            if (state.isStreamingGPS) {
                              state.stopStreamingGPS();
                            } else {
                              state.startStreamingGPS(
                                _selectedVehicleId!,
                                _simulateGps,
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: state.isStreamingGPS
                          ? Colors.redAccent
                          : const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      state.isStreamingGPS
                          ? 'Stop GPS Broadcast'
                          : 'Start GPS Broadcast',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// NOTIFICATIONS CENTER SCREEN (Premium Floating Cards & List)
// =====================================================================
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  String _formatTimeAgo(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return 'Just now';
    try {
      final DateTime parsed = DateTime.parse(dateTimeStr).toLocal();
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(parsed);

      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return 'Recent';
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'booking':
        return Icons.confirmation_number_rounded;
      case 'trip_update':
        return Icons.event_note_rounded;
      case 'verification':
        return Icons.verified_user_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'booking':
        return const Color(0xFF2563EB); // Matte Orange
      case 'trip_update':
        return const Color(0xFF0A2540); // Navy Blue
      case 'verification':
        return const Color(0xFF10B981); // Emerald Green
      default:
        return const Color(0xFF64748B); // Slate Grey
    }
  }

  void _handleNotificationTap(
      BuildContext context, AppState state, Map<String, dynamic> noti) {
    if (noti['type'] == 'booking' ||
        (noti['title'] ?? '').toLowerCase().contains('booking')) {
      Map<String, dynamic>? targetBooking;
      if (state.bookings.isNotEmpty) {
        final msg = (noti['message'] ?? '').toString();
        for (var b in state.bookings) {
          final reg = b['reg']?.toString() ?? '';
          final idStr = b['id']?.toString() ?? '';
          if ((reg.isNotEmpty && msg.contains(reg)) ||
              (idStr.isNotEmpty && msg.contains(idStr.substring(0, 8)))) {
            targetBooking = b;
            break;
          }
        }
        targetBooking ??= state.bookings.first;
      }

      if (targetBooking != null) {
        _showTicketDialog(context, targetBooking);
      } else {
        SeatyNotifications.show(
          context,
          'Opening your tickets...',
        );
      }
    }
  }

  void _showTicketDialog(BuildContext context, Map<String, dynamic> b) {
    final ticketCode =
        'TKT-${b['id'].toString().substring(0, 8).toUpperCase()}';
    final seats = (b['seats'] as List?)?.join(', ') ?? '';
    final formattedPrice =
        double.tryParse(b['price'].toString())?.toStringAsFixed(2) ??
        b['price'].toString();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.confirmation_number_rounded, color: Color(0xFF2563EB), size: 24),
              SizedBox(width: 8),
              Text(
                'Digital Boarding Pass',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0A2540),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            ticketCode,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0A2540),
                              fontSize: 12,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'CONFIRMED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Text(
                        '${b['origin']} ➔ ${b['destination']}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0A2540),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Departure: ${b['departure']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Bus: ${b['bus_name']} (${b['reg']})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Seat(s): $seats',
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Rs. $formattedPrice',
                            style: const TextStyle(
                              color: Color(0xFF0A2540),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox(
                    width: 150,
                    height: 150,
                    child: QrImageView(
                      data: b['id'].toString(),
                      version: QrVersions.auto,
                      size: 150.0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Show this QR ticket to the conductor when boarding.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final list = state.notifications;
    final unreadCount = state.unreadNotificationsCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Modern off-white background
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0A2540),
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        actions: [
          if (unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: () {
                  state.markAllNotificationsAsRead();
                  SeatyNotifications.show(
                    context,
                    'All notifications marked as read',
                  );
                },
                icon: const Icon(
                  Icons.done_all_rounded,
                  size: 18,
                  color: Color(0xFF0A2540),
                ),
                label: const Text(
                  'Mark all read',
                  style: TextStyle(
                    color: Color(0xFF0A2540),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: list.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 100,
                    width: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2540).withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      size: 48,
                      color: Color(0xFF0A2540),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'All caught up!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0A2540),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No notifications yet. Enjoy your day!',
                    style: TextStyle(
                      fontSize: 14,
                      color: const Color(0xFF0A2540).withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await state.fetchNotifications();
              },
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final noti = list[index];
                  final String notiId = noti['id']?.toString() ?? '';
                  final String title = noti['title'] ?? 'Alert';
                  final String message = noti['message'] ?? '';
                  final String type = noti['type'] ?? 'system';
                  final bool isRead =
                      noti['is_read'] == true || noti['is_read'] == 1;
                  final String timeAgo = _formatTimeAgo(noti['created_at']);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isRead
                          ? Colors.white
                          : const Color(
                              0xFFF1F5F9,
                            ), // Subtle greyish-blue for unread
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: isRead
                            ? Colors.black.withOpacity(0.05)
                            : const Color(0xFF0A2540).withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          if (!isRead && notiId.isNotEmpty) {
                            state.markNotificationAsRead(notiId);
                          }
                          _handleNotificationTap(context, state, noti);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _getColorForType(
                                    type,
                                  ).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _getIconForType(type),
                                  color: _getColorForType(type),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: isRead
                                                  ? FontWeight.bold
                                                  : FontWeight.w800,
                                              color: const Color(0xFF0A2540),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          timeAgo,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: const Color(
                                              0xFF0A2540,
                                            ).withOpacity(0.5),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      message,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: const Color(
                                          0xFF0A2540,
                                        ).withOpacity(0.7),
                                        height: 1.4,
                                      ),
                                    ),
                                    if (!isRead)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF2563EB),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Tap to mark as read',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF2563EB),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
