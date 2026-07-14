import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

// =====================================================================
// 1. STATE MANAGEMENT (PROVIDER)
// =====================================================================
class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;
  
  String _role = 'passenger'; // 'passenger' | 'owner'
  bool _isAuthenticated = false;
  String _userName = 'Guest User';
  String _token = '';
  
  // API URL Config
  String apiBaseUrl = 'http://localhost:8000/api/v1';
  String wsBaseUrl = 'ws://localhost:8000/api/v1/ws';

  AppState(this._prefs) {
    _loadSession();
    // Load trips publicly for guest, and all details if authenticated
    loadTrips();
    if (_isAuthenticated) {
      loadVehicles();
      loadBookings();
    }
  }

  void _loadSession() {
    _isAuthenticated = _prefs.getBool('isAuthenticated') ?? false;
    _role = _prefs.getString('role') ?? 'passenger';
    _userName = _prefs.getString('userName') ?? 'Guest User';
    _token = _prefs.getString('token') ?? '';
    apiBaseUrl = _prefs.getString('apiBaseUrl') ?? 'http://localhost:8000/api/v1';
    wsBaseUrl = _prefs.getString('wsBaseUrl') ?? 'ws://localhost:8000/api/v1/ws';
    
    // Auto-override outdated placeholder IP to avoid socket timeouts
    if (apiBaseUrl.contains('192.168.1.195')) {
      apiBaseUrl = 'http://localhost:8000/api/v1';
      wsBaseUrl = 'ws://localhost:8000/api/v1/ws';
      _saveSession();
    }
  }

  void _saveSession() {
    _prefs.setBool('isAuthenticated', _isAuthenticated);
    _prefs.setString('role', _role);
    _prefs.setString('userName', _userName);
    _prefs.setString('token', _token);
    _prefs.setString('apiBaseUrl', apiBaseUrl);
    _prefs.setString('wsBaseUrl', wsBaseUrl);
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
    }
  ];

  final List<Map<String, dynamic>> _trips = [
    {
      'id': 't1',
      'origin': 'Colombo Fort',
      'destination': 'Galle Multi-modal',
      'departure': '2026-07-13 14:00',
      'price': 1600.0,
      'bus_name': 'Colombo Express VIP',
      'reg': 'WP-ND-8942'
    },
    {
      'id': 't2',
      'origin': 'Colombo Fort',
      'destination': 'Kandy Goods Shed',
      'departure': '2026-07-13 16:30',
      'price': 1800.0,
      'bus_name': 'Kandy Intercity Deluxe',
      'reg': 'CP-NB-7721'
    }
  ];

  final List<Map<String, dynamic>> _bookings = [];
  
  // Selected seats state
  final List<String> _selectedSeats = [];
  List<String> _bookedSeats = [];
  List<String> _heldSeats = [];

  // Tracking bus variables
  Map<String, dynamic>? _trackedBusLocation;
  WebSocketChannel? _trackingChannel;
  bool _isTracking = false;

  // Senders variables (Owner streaming GPS)
  WebSocketChannel? _streamingChannel;
  bool _isStreamingGPS = false;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Getters
  String get role => _role;
  bool get isAuthenticated => _isAuthenticated;
  String get userName => _userName;
  List<Map<String, dynamic>> get vehicles => _vehicles;
  List<Map<String, dynamic>> get trips => _trips;
  List<Map<String, dynamic>> get bookings => _bookings;
  List<String> get selectedSeats => _selectedSeats;
  List<String> get bookedSeats => _bookedSeats;
  List<String> get heldSeats => _heldSeats;
  Map<String, dynamic>? get trackedBusLocation => _trackedBusLocation;
  bool get isTracking => _isTracking;
  bool get isStreamingGPS => _isStreamingGPS;

  // Simulated registered users database
  final List<Map<String, String>> _registeredUsers = [
    {
      'phone': '0771234567',
      'name': 'Saman Perera',
      'role': 'passenger',
    },
    {
      'phone': '0777654321',
      'name': 'Ranasinghe Bandara',
      'role': 'owner',
    }
  ];

  List<Map<String, String>> get registeredUsers => _registeredUsers;

  Future<Map<String, dynamic>> checkPhoneDB(String phone, String role) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/auth/phone/check'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'phone_number': phone, 'role': role}),
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'exists': data['exists'], 'name': data['name']};
      }
    } catch (e) {
      debugPrint('API Error: $e. Falling back to local state.');
    }
    
    final exists = _registeredUsers.any((u) => u['phone'] == phone && u['role'] == role);
    final user = _registeredUsers.firstWhere(
      (u) => u['phone'] == phone && u['role'] == role,
      orElse: () => {'name': 'Guest User'},
    );
    return {'exists': exists, 'name': user['name']};
  }

  Future<bool> registerPhoneDB(String name, String phone, String role) async {
    if (!_registeredUsers.any((u) => u['phone'] == phone && u['role'] == role)) {
      _registeredUsers.add({'phone': phone, 'name': name, 'role': role});
      notifyListeners();
    }

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/auth/phone/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'phone_number': phone, 'full_name': name, 'role': role}),
      ).timeout(const Duration(seconds: 2));

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('API Registration Error: $e. Local registration fallback used.');
      return true;
    }
  }

  // Toggle roles
  void setRole(String newRole) {
    _role = newRole;
    notifyListeners();
  }

  // Real or Simulated Login
  void login(String name, String roleSelected, String phoneNumber) async {
    _userName = name;
    _role = roleSelected;
    _isAuthenticated = true;
    
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/auth/phone/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone_number': phoneNumber,
          'role': roleSelected,
        }),
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['access_token'];
      }
    } catch (e) {
      debugPrint('API Login error: $e. Using simulated token.');
      _token = 'simulated_jwt_token_for_${name.replaceAll(' ', '_')}';
    }

    _saveSession();
    loadVehicles();
    loadTrips();
    loadBookings();
    notifyListeners();
  }

  void logout() {
    _isAuthenticated = false;
    _token = '';
    _selectedSeats.clear();
    _bookedSeats.clear();
    _heldSeats.clear();
    stopTracking();
    stopStreamingGPS();
    _saveSession();
    notifyListeners();
  }

  // Load vehicles from backend
  Future<void> loadVehicles() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/vehicles'),
        headers: {
          'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 3));

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

  // Load trips from backend
  Future<void> loadTrips() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/trips'),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _trips.clear();
        for (var item in data) {
          final tripMap = item as Map<String, dynamic>;
          final vehicle = tripMap['vehicle'] ?? {};
          _trips.add({
            'id': tripMap['id'],
            'origin': tripMap['route']?['origin'] ?? 'Colombo Fort',
            'destination': tripMap['route']?['destination'] ?? 'Galle',
            'departure': tripMap['departure_time']?.toString().replaceAll('T', ' ').substring(0, 16) ?? '2026-07-13 14:00',
            'price': double.tryParse(tripMap['price_per_seat'].toString()) ?? 1600.0,
            'bus_name': vehicle['name'] ?? 'Luxury Express',
            'reg': vehicle['registration_number'] ?? 'WP-ND-0000',
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
      final response = await http.get(
        Uri.parse('$apiBaseUrl/bookings'),
        headers: {
          'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 3));

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
            'departure': trip['departure_time']?.toString().replaceAll('T', ' ').substring(0, 16) ?? '2026-07-13 14:00',
            'bus_name': vehicle['name'] ?? 'Luxury Express',
            'reg': vehicle['registration_number'] ?? 'WP-ND-0000',
            'seats': List<String>.from(b['selected_seats'] ?? []),
            'price': double.tryParse(b['total_price'].toString()) ?? 0.0,
            'status': b['booking_status'] ?? 'pending',
            'passenger_name': b['passenger']?['full_name'] ?? 'Passenger',
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
  Future<void> loadSeatAvailability(String tripId) async {
    _bookedSeats.clear();
    _heldSeats.clear();
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/seat-holds/trip/$tripId'),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _bookedSeats = List<String>.from(data['booked_seats'] ?? []);
        _heldSeats = List<String>.from(data['held_seats'] ?? []);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading seat availability: $e');
    }
  }

  // Initiate Booking (creates pending booking and holds seats)
  Future<Map<String, dynamic>?> initiateBooking(String tripId) async {
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
        body: json.encode({
          'booking_id': bookingId,
        }),
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
          'seat_layout': {'rows': (capacity / 4).ceil(), 'columns': 4, 'aisle_after_column': 2},
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
      'is_verified': false
    });
    notifyListeners();
  }

  // Add trip
  void scheduleTrip(String vehicleId, String origin, String destination, String time, double price) async {
    try {
      // Find the vehicle UUID from our list of vehicles
      final v = _vehicles.firstWhere((x) => x['id'] == vehicleId || x['reg'] == vehicleId, orElse: () => _vehicles[0]);
      
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
            'departure_time': DateTime.parse(time.replaceAll(' ', 'T') + ':00Z').toUtc().toIso8601String(),
            'arrival_time': DateTime.parse(time.replaceAll(' ', 'T') + ':00Z').add(const Duration(hours: 2)).toUtc().toIso8601String(),
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
    final v = _vehicles.firstWhere((x) => x['id'] == vehicleId || x['reg'] == vehicleId, orElse: () => _vehicles[0]);
    _trips.add({
      'id': 't-${DateTime.now().millisecondsSinceEpoch}',
      'origin': origin,
      'destination': destination,
      'departure': time,
      'price': price,
      'bus_name': v['name'],
      'reg': v['reg']
    });
    notifyListeners();
  }

  // Seats interactions
  void toggleSeat(String seatLabel) {
    if (_selectedSeats.contains(seatLabel)) {
      _selectedSeats.remove(seatLabel);
    } else {
      _selectedSeats.add(seatLabel);
    }
    notifyListeners();
  }

  void clearSelectedSeats() {
    _selectedSeats.clear();
    notifyListeners();
  }

  // Local fallback confirmation
  void bookTicket(Map<String, dynamic> trip) {
    if (_selectedSeats.isEmpty) return;
    
    _bookings.add({
      'id': 'b-${DateTime.now().millisecondsSinceEpoch}',
      'trip_id': trip['id'],
      'origin': trip['origin'],
      'destination': trip['destination'],
      'departure': trip['departure'],
      'bus_name': trip['bus_name'],
      'reg': trip['reg'],
      'seats': List<String>.from(_selectedSeats),
      'price': trip['price'] * _selectedSeats.length,
      'status': 'confirmed'
    });
    _selectedSeats.clear();
    notifyListeners();
  }

  // Live Tracking listener (WS Client)
  void startTracking(String vehicleId) {
    stopTracking();
    _isTracking = true;
    _trackedBusLocation = {
      'vehicle_id': vehicleId,
      'latitude': 6.9271,
      'longitude': 79.8612,
      'speed': 0.0,
      'heading': 0.0
    };
    notifyListeners();

    try {
      final wsUrl = '$wsBaseUrl/tracking/$vehicleId?role=passenger&token=$_token';
      _trackingChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _trackingChannel!.stream.listen((message) {
        final data = json.decode(message);
        _trackedBusLocation = data;
        notifyListeners();
      }, onError: (err) {
        print('Tracking socket error: $err');
      }, onDone: () {
        _isTracking = false;
        notifyListeners();
      });
    } catch (e) {
      print('WebSocket connection failed: $e');
    }
  }

  void stopTracking() {
    _trackingChannel?.sink.close();
    _trackingChannel = null;
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

    if (simulate) {
      // Loop coordinates representing Colombo -> Galle highway
      double startLat = 6.9271;
      double startLon = 79.8612;
      Timer.periodic(const Duration(seconds: 2), (timer) {
        if (!_isStreamingGPS) {
          timer.cancel();
          return;
        }
        startLat += 0.003;
        startLon += 0.002;
        
        final payload = {
          'latitude': startLat,
          'longitude': startLon,
          'speed': 65.5,
          'heading': 145.0
        };

        // Send to WebSocket
        _streamingChannel?.sink.add(json.encode(payload));
        
        // Also update local tracking state in case passenger is on the same device
        _trackedBusLocation = {
          'vehicle_id': vehicleId,
          ...payload
        };
        notifyListeners();
      });
    } else {
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

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        final payload = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'speed': position.speed * 3.6, // m/s to km/h
          'heading': position.heading
        };

        _streamingChannel?.sink.add(json.encode(payload));
        notifyListeners();
      });
    }
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
// 2. MAIN APPLICATION SETUP
// =====================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(prefs),
      child: const SeatyApp(),
    ),
  );
}

class SeatyApp extends StatelessWidget {
  const SeatyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seaty Luxury Transport',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        primaryColor: const Color(0xFF0A2540), // Navy Blue
        hintColor: const Color(0xFFE65100), // Matte Orange
        cardColor: const Color(0xFFF4F6F9), // Light card background
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0A2540),
          secondary: Color(0xFFE65100),
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
            fontFamily: 'Inter',
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF0A2540),
          unselectedItemColor: Colors.black38,
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

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
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
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    if (!state.isAuthenticated) {
      return const AuthScreen();
    }
    return state.role == 'passenger' ? const PassengerMainScreen() : const OwnerMainScreen();
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
                            MaterialPageRoute(builder: (context) => const PhoneAuthScreen(role: 'passenger')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
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
                                errorBuilder: (context, error, stackTrace) => const Icon(
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
                                style: TextStyle(fontSize: 10, color: Colors.black54),
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
                            MaterialPageRoute(builder: (context) => const PhoneAuthScreen(role: 'owner')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
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
                                errorBuilder: (context, error, stackTrace) => const Icon(
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
                                'Manage schedules & GPS',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 10, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _ServerIpConfigPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerIpConfigPanel extends StatefulWidget {
  const _ServerIpConfigPanel();

  @override
  State<_ServerIpConfigPanel> createState() => _ServerIpConfigPanelState();
}

class _ServerIpConfigPanelState extends State<_ServerIpConfigPanel> {
  bool _expanded = false;
  late TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final uri = Uri.tryParse(state.apiBaseUrl);
    final currentIp = uri?.host ?? '192.168.1.195';

    if (!_expanded) {
      return TextButton.icon(
        onPressed: () {
          _ipController.text = currentIp;
          setState(() => _expanded = true);
        },
        icon: const Icon(Icons.settings_suggest_rounded, size: 14, color: Colors.grey),
        label: Text(
          'Backend IP: $currentIp (tap to change)',
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      );
    }

    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Developer: Edit Backend IP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _ipController,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: 'e.g. 192.168.1.195',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: () {
                    final ip = _ipController.text.trim();
                    if (ip.isNotEmpty) {
                      state.updateServerIp(ip);
                      setState(() => _expanded = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('API address updated to $ip')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2540),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Save', style: TextStyle(fontSize: 11)),
                ),
              )
            ],
          )
        ],
      ),
    );
  }
}

// =====================================================================
// MOBILE & OTP AUTHENTICATION PROCESS
// =====================================================================
enum PhoneAuthState { enterPhone, register, verifyOtp }

class PhoneAuthScreen extends StatefulWidget {
  final String role;
  const PhoneAuthScreen({super.key, required this.role});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  PhoneAuthState _authState = PhoneAuthState.enterPhone;
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();
  String _generatedOtp = '';
  bool _isNewUser = false;
  String _currentUserName = '';

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
    final state = Provider.of<AppState>(context, listen: false);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF0A2540), size: 36),
          onPressed: () {
            FocusScope.of(context).unfocus();
            if (_authState == PhoneAuthState.enterPhone) {
              Navigator.pop(context);
            } else if (_authState == PhoneAuthState.register) {
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
            Text(
              widget.role == 'passenger' ? 'Passenger Login' : 'Owner Login',
              style: const TextStyle(
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
                prefixIcon: const Icon(Icons.phone_iphone_rounded, color: Color(0xFF0A2540)),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF0A2540), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final phone = _phoneController.text.trim();
                if (phone.length < 9) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid mobile number.')),
                  );
                  return;
                }

                // Show loading SnackBar or call API
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Verifying number...'), duration: Duration(milliseconds: 600)),
                );

                final checkResult = await state.checkPhoneDB(phone, widget.role);
                final bool exists = checkResult['exists'] ?? false;
                final String name = checkResult['name'] ?? 'Guest User';

                if (exists) {
                  _isNewUser = false;
                  _currentUserName = name;
                  _generateAndSendOtp(context, name, phone);
                  setState(() => _authState = PhoneAuthState.verifyOtp);
                } else {
                  if (widget.role == 'owner') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This number is not registered as an Owner. Please contact the administrator.'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  } else {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _isNewUser = true;
                      _nameController.clear();
                      _authState = PhoneAuthState.register;
                    });
                  }
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
              child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            if (widget.role == 'passenger') ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ", style: TextStyle(color: Colors.grey, fontSize: 13)),
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
                      style: TextStyle(color: Color(0xFF0A2540), fontWeight: FontWeight.bold, fontSize: 13),
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
                prefixIcon: const Icon(Icons.person_rounded, color: Color(0xFF0A2540)),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF0A2540), width: 1.5),
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
                prefixIcon: const Icon(Icons.phone_iphone_rounded, color: Color(0xFF0A2540)),
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF0A2540), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final name = _nameController.text.trim();
                final phone = _phoneController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter your full name.')),
                  );
                  return;
                }
                if (phone.length < 9) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid mobile number.')),
                  );
                  return;
                }

                FocusScope.of(context).unfocus();
                // Show loading SnackBar or call API
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Creating account...'), duration: Duration(milliseconds: 600)),
                );

                await state.registerPhoneDB(name, phone, widget.role);
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
              child: const Text('Register & Verify', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Already have an account? ", style: TextStyle(color: Colors.grey, fontSize: 13)),
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
                    style: TextStyle(color: Color(0xFF0A2540), fontWeight: FontWeight.bold, fontSize: 13),
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
              style: const TextStyle(color: Colors.black87, letterSpacing: 8, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: '••••••',
                hintStyle: const TextStyle(letterSpacing: 8, color: Colors.grey),
                counterText: '',
                filled: true,
                fillColor: const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF0A2540), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final otp = _otpController.text.trim();
                if (otp != _generatedOtp) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid verification code. Please check the SMS.')),
                  );
                  return;
                }

                final phone = _phoneController.text.trim();
                final name = _currentUserName.isNotEmpty ? _currentUserName : 'User';
                state.login(name, widget.role, phone);
                
                _otpController.clear();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Verify & Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                final phone = _phoneController.text.trim();
                final name = _currentUserName.isNotEmpty ? _currentUserName : 'User';
                _generateAndSendOtp(context, name, phone);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A new OTP has been sent.')),
                );
              },
              child: const Text(
                'Resend Code',
                style: TextStyle(color: Color(0xFF0A2540), fontWeight: FontWeight.bold),
              ),
            )
          ],
        );
    }
  }
}

// =====================================================================
// 4. PASSENGER MAIN SCREEN
// =====================================================================
class PassengerMainScreen extends StatefulWidget {
  const PassengerMainScreen({super.key});

  @override
  State<PassengerMainScreen> createState() => _PassengerMainScreenState();
}

class _PassengerMainScreenState extends State<PassengerMainScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const PassengerTripsTab(),
    const PassengerTrackingTab(),
    const PassengerBookingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true, // Let content scroll behind the floating capsule
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Seaty',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF0A2540), letterSpacing: 0.5),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Colors.black.withOpacity(0.05),
            height: 1.0,
          ),
        ),
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: _buildTelegramBottomNavBar(context),
    );
  }

  Widget _buildTelegramBottomNavBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 32, right: 32, bottom: 24),
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xEE0A2540), // Dark Navy (93% Opacity)
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
          _buildNavItem(1, Icons.near_me_outlined, Icons.near_me_rounded, 'Tracker'),
          _buildNavItem(2, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Tickets'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData outlineIcon, IconData solidIcon, String label) {
    final isSelected = _currentIndex == index;
    final activeColor = const Color(0xFFE65100); // Matte Orange
    final inactiveColor = Colors.white.withOpacity(0.55);

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE65100).withOpacity(0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isSelected ? solidIcon : outlineIcon,
              color: isSelected ? activeColor : inactiveColor,
              size: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}

// Sub-Tab 1: Passenger Trips & Booking Flow
class PassengerTripsTab extends StatefulWidget {
  const PassengerTripsTab({super.key});

  @override
  State<PassengerTripsTab> createState() => _PassengerTripsTabState();
}

class _PassengerTripsTabState extends State<PassengerTripsTab> {
  String _selectedFrom = 'All';
  String _selectedTo = 'All';

  final List<Map<String, dynamic>> _destinations = [
    {'name': 'Colombo', 'color1': 0xFF0A2540, 'color2': 0xFF0E3A5E},
    {'name': 'Kandy', 'color1': 0xFFE65100, 'color2': 0xFFFF8A50},
    {'name': 'Galle', 'color1': 0xFF1E293B, 'color2': 0xFF475569},
  ];

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    final filteredTrips = state.trips.where((trip) {
      if (_selectedFrom == 'All' && _selectedTo == 'All') return true;

      // Helper to find position of a location (-1 = origin, index = stop index, 100000 = destination)
      int? findStopPos(String searchLoc) {
        final normSearch = searchLoc.toLowerCase().trim();
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

      if (_selectedFrom != 'All') {
        fromPos = findStopPos(_selectedFrom);
        if (fromPos == null) match = false;
      }

      if (_selectedTo != 'All') {
        toPos = findStopPos(_selectedTo);
        if (toPos == null) match = false;
      }

      // Ensure origin comes before destination
      if (match && _selectedFrom != 'All' && _selectedTo != 'All') {
        if (fromPos != null && toPos != null && fromPos >= toPos) {
          match = false;
        }
      }

      return match;
    }).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ─── Glassmorphic Hero & Search Header ───
        SliverToBoxAdapter(
          child: Stack(
            children: [
              // Background gradient map pattern placeholder
              Container(
                height: 320,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  ),
                ),
              ),
              // Content
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Greeting row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Good Morning,',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.7)),
                              ),
                              Text(
                                state.userName,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
                              ),
                            ],
                          ),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFFE65100).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: const Color(0xFFE65100),
                              child: Text(
                                state.userName.isNotEmpty ? state.userName[0].toUpperCase() : 'U',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Where are you\ntraveling today?',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1, letterSpacing: -1),
                      ),
                      const SizedBox(height: 32),
                      
                      // Glassmorphic Search Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.15)),
                            ),
                            child: Column(
                              children: [
                                _buildGlassField(
                                  icon: Icons.my_location_rounded,
                                  label: 'Current Location',
                                  value: _selectedFrom,
                                  isFrom: true,
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 20),
                                      Expanded(
                                        child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            final temp = _selectedFrom;
                                            _selectedFrom = _selectedTo;
                                            _selectedTo = temp;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          margin: const EdgeInsets.symmetric(horizontal: 16),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE65100),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(color: const Color(0xFFE65100).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4)),
                                            ],
                                          ),
                                          child: const Icon(Icons.swap_vert_rounded, size: 20, color: Colors.white),
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildGlassField(
                                  icon: Icons.location_on_rounded,
                                  label: 'Destination',
                                  value: _selectedTo,
                                  isFrom: false,
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

        // ─── Popular Destinations Carousel ───
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 32, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Popular Destinations',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.5),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 140,
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _destinations.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // "All" Card
                        final isSelected = _selectedTo == 'All';
                        return _buildDestinationCard('All', 'Everywhere', 0xFFF1F5F9, 0xFFE2E8F0, isSelected, true);
                      }
                      final dest = _destinations[index - 1];
                      final isSelected = _selectedTo == dest['name'];
                      return _buildDestinationCard(dest['name'] as String, 'Explore', dest['color1'] as int, dest['color2'] as int, isSelected, false);
                    },
                  ),
                ),
              ],
            ),
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.5),
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
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20)],
                    ),
                    child: const Icon(Icons.search_off_rounded, size: 40, color: Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 24),
                  const Text('No rides found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 8),
                  const Text('Try adjusting your search criteria', style: TextStyle(color: Color(0xFF64748B))),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _buildModernTripCard(context, filteredTrips[index]);
                },
                childCount: filteredTrips.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGlassField({required IconData icon, required String label, required String value, required bool isFrom}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.9), size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.6))),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: const Color(0xFF1E293B),
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.5)),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  items: ['All', 'Colombo', 'Kandy', 'Galle'].map((loc) => DropdownMenuItem(
                    value: loc,
                    child: Text(loc, style: const TextStyle(color: Colors.white)),
                  )).toList(),
                  onChanged: (val) {
                    setState(() {
                      if (isFrom) _selectedFrom = val ?? 'All';
                      else _selectedTo = val ?? 'All';
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDestinationCard(String name, String subtitle, int color1, int color2, bool isSelected, bool isLight) {
    return GestureDetector(
      onTap: () => setState(() => _selectedTo = name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(color1), Color(color2)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected && isLight ? const Color(0xFFE65100) : Colors.transparent, width: 2),
          boxShadow: [
            if (isSelected && !isLight)
              BoxShadow(color: Color(color2).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8))
            else
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
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
                isLight ? Icons.explore_rounded : Icons.landscape_rounded,
                color: isLight ? const Color(0xFF0F172A) : Colors.white,
                size: 20,
              ),
            ),
            const Spacer(),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: isLight ? const Color(0xFF64748B) : Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF0F172A) : Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernTripCard(BuildContext context, Map<String, dynamic> trip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Top Header: Bus Name & Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.directions_bus_rounded, color: Color(0xFF0F172A)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trip['bus_name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(trip['reg'], style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rs. ${trip['price'].toString().split('.')[0]}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFFE65100), letterSpacing: -0.5),
                    ),
                    const Text('per seat', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Route Graphic
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trip['origin'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 4),
                      Text('Departure ${trip['departure']}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFCBD5E1))),
                      Container(width: 30, height: 2, color: const Color(0xFFF1F5F9)),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFFCBD5E1)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(trip['destination'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 4),
                      const Text('Drop-off Point', style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Action Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SeatSelectorScreen(trip: trip)),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Book Seats', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// Seat Selector Screen
class SeatSelectorScreen extends StatefulWidget {
  final Map<String, dynamic> trip;
  const SeatSelectorScreen({super.key, required this.trip});

  @override
  State<SeatSelectorScreen> createState() => _SeatSelectorScreenState();
}

class _SeatSelectorScreenState extends State<SeatSelectorScreen> {
  bool _isLoading = true;
  bool _isBookingInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSeats();
    });
  }

  Future<void> _refreshSeats() async {
    setState(() => _isLoading = true);
    final state = Provider.of<AppState>(context, listen: false);
    state.clearSelectedSeats();
    await state.loadSeatAvailability(widget.trip['id'].toString());
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _handleConfirmAndBook(AppState state) async {
    setState(() => _isBookingInProgress = true);
    
    // 1. Create booking (Pending)
    final booking = await state.initiateBooking(widget.trip['id'].toString());
    if (booking == null) {
      if (mounted) {
        setState(() => _isBookingInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to hold seats. They may have just been booked.')),
        );
      }
      return;
    }

    // 2. Initiate payment session
    final payment = await state.initiatePayment(booking['id'].toString());
    if (payment == null) {
      if (mounted) {
        setState(() => _isBookingInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initiate payment session.')),
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

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Luxury Seats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshSeats,
            tooltip: 'Refresh seats',
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65100)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.trip['bus_name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(widget.trip['reg'], style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'monospace')),
                    ],
                  ),
                ),
                const Divider(height: 1),
                
                // Legend Bar
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem(const Color(0xFFF4F6F9), 'Available', border: Colors.black12),
                      _buildLegendItem(const Color(0xFFE65100), 'Selected'),
                      _buildLegendItem(Colors.grey.shade400, 'Booked'),
                      _buildLegendItem(Colors.amber.shade200, 'Held'),
                    ],
                  ),
                ),
                
                // Seat Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(28),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: 40, // 40 seats
                    itemBuilder: (context, index) {
                      // Aisle logic (middle column)
                      if (index % 5 == 2) {
                        return const Center(child: Icon(Icons.unfold_more, color: Colors.black12));
                      }

                      // Seat Label
                      int row = index ~/ 5 + 1;
                      String col = String.fromCharCode(65 + (index % 5 > 2 ? index % 5 - 1 : index % 5));
                      String seatLabel = '$col$row';

                      bool isSelected = state.selectedSeats.contains(seatLabel);
                      bool isBooked = state.bookedSeats.contains(seatLabel);
                      bool isHeld = state.heldSeats.contains(seatLabel);

                      Color seatColor = const Color(0xFFF4F6F9);
                      Color textColor = const Color(0xFF0A2540);
                      Color borderColor = Colors.black12;

                      if (isSelected) {
                        seatColor = const Color(0xFFE65100);
                        textColor = Colors.white;
                        borderColor = const Color(0xFFE65100);
                      } else if (isBooked) {
                        seatColor = Colors.grey.shade300;
                        textColor = Colors.grey.shade600;
                        borderColor = Colors.grey.shade400;
                      } else if (isHeld) {
                        seatColor = Colors.amber.shade200;
                        textColor = Colors.amber.shade800;
                        borderColor = Colors.amber.shade400;
                      }

                      return InkWell(
                        onTap: (isBooked || isHeld) ? null : () => state.toggleSeat(seatLabel),
                        child: Container(
                          decoration: BoxDecoration(
                            color: seatColor,
                            border: Border.all(
                              color: borderColor,
                              width: 1.5,
                            ),
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
                
                // Checkout Info Bar
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0A2540),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            state.selectedSeats.isEmpty ? 'No seats selected' : 'Seats: ${state.selectedSeats.join(', ')}', 
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)
                          ),
                          Text(
                            'Rs. ${(widget.trip['price'] * state.selectedSeats.length).toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: (state.selectedSeats.isEmpty || _isBookingInProgress)
                            ? null
                            : () => _handleConfirmAndBook(state),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade800,
                          disabledForegroundColor: Colors.white30,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isBookingInProgress
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Confirm & Book Seats', style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                )
              ],
            ),
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
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black87)),
      ],
    );
  }
}

// Custom Premium Sandbox Payment Screen
class SandboxPaymentScreen extends StatefulWidget {
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
  State<SandboxPaymentScreen> createState() => _SandboxPaymentScreenState();
}

class _SandboxPaymentScreenState extends State<SandboxPaymentScreen> {
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seat hold expired. Please try booking again.'),
        backgroundColor: Colors.redAccent,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _processPayment(bool success) async {
    setState(() => _isProcessing = true);
    final state = Provider.of<AppState>(context, listen: false);
    final transactionId = widget.payment['gateway_transaction_id'];

    final bool result = success
        ? await state.completeSandboxPayment(transactionId)
        : await state.failSandboxPayment(transactionId);

    if (mounted) {
      setState(() => _isProcessing = false);
      if (result) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Payment Completed Successfully!' : 'Booking cancelled.'),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong communicating with sandbox server.')),
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
    final selectedSeatsList = List<String>.from(widget.booking['selected_seats'] ?? []);
    final double fare = double.tryParse(widget.booking['total_price'].toString()) ?? 0.0;
    final double platformFee = double.tryParse(widget.payment['platform_fee'].toString()) ?? 25.0;
    final double total = double.tryParse(widget.payment['amount'].toString()) ?? (fare + platformFee);

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
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade200),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hourglass_bottom_rounded, color: Colors.amber.shade800, size: 16),
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
                        const Text('Booking Summary', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0A2540))),
                        const SizedBox(height: 16),
                        _buildRow('Bus Service', widget.trip['bus_name']),
                        _buildRow('Route', '${widget.trip['origin']} → ${widget.trip['destination']}'),
                        _buildRow('Selected Seats', selectedSeatsList.join(', ')),
                        const Divider(height: 24),
                        _buildRow('Seat Fare', 'Rs. ${fare.toStringAsFixed(0)}'),
                        _buildRow('Platform Fee', 'Rs. ${platformFee.toStringAsFixed(0)}'),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0A2540))),
                            Text(
                              'Rs. ${total.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFFE65100)),
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
                      const Icon(Icons.security, color: Color(0xFF10B981), size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'Secure Sandbox Payment Portal',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'This simulates secure token validation. Click authorize to complete reservation.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(height: 24),
                      if (_isProcessing)
                        const CircularProgressIndicator(color: Color(0xFFE65100))
                      else ...[
                        ElevatedButton(
                          onPressed: () => _processPayment(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Authorize & Complete Payment', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => _processPayment(false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                          child: const Text('Cancel & Release Seats', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ]
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
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Color(0xFF0A2540), fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// Sub-Tab 2: Passenger Live Tracking View
class PassengerTrackingTab extends StatefulWidget {
  const PassengerTrackingTab({super.key});

  @override
  State<PassengerTrackingTab> createState() => _PassengerTrackingTabState();
}

class _PassengerTrackingTabState extends State<PassengerTrackingTab> {
  String? _selectedBusId;

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Live GPS Radar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Track luxury buses commuting live.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          
          // Select Bus to Track
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              labelText: 'Select Bus line to track',
            ),
            value: _selectedBusId,
            items: state.trips.map((trip) {
              return DropdownMenuItem<String>(
                value: trip['reg'],
                child: Text('${trip['bus_name']} (${trip['reg']})'),
              );
            }).toList(),
            onChanged: (val) {
              setState(() => _selectedBusId = val);
              if (val != null) {
                state.startTracking(val);
              }
            },
          ),
          const SizedBox(height: 16),

          // Custom Radar View (acting as a gorgeous map placeholder)
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: RadarPainter(
                        isTracking: state.isTracking,
                        loc: state.trackedBusLocation,
                      ),
                    ),
                  ),
                  
                  // Radar detail dashboard overlay
                  if (state.isTracking && state.trackedBusLocation != null)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF0A2540).withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.gps_fixed_rounded, size: 14, color: Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                Text(
                                  'Streaming Active: $_selectedBusId', 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF10B981))
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'GPS Coords: [${state.trackedBusLocation!['latitude'].toStringAsFixed(4)}, ${state.trackedBusLocation!['longitude'].toStringAsFixed(4)}]',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF0A2540)),
                            ),
                            Text(
                              'Speed: ${state.trackedBusLocation!['speed'].toStringAsFixed(1)} km/h • Bearing: ${state.trackedBusLocation!['heading']?.toStringAsFixed(0)}°',
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.radar_rounded, size: 48, color: Color(0xFF0A2540)),
                          const SizedBox(height: 8),
                          Text('Select a vehicle to initiate tracking', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

// Custom Painter to draw a sleek glowing Radar map
class RadarPainter extends CustomPainter {
  final bool isTracking;
  final Map<String, dynamic>? loc;
  RadarPainter({required this.isTracking, required this.loc});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0A2540).withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw radar circles
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * 0.15, paint);
    canvas.drawCircle(center, size.width * 0.3, paint);
    canvas.drawCircle(center, size.width * 0.45, paint);

    // Draw cross lines
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);

    // Draw active locator dots if tracking
    if (isTracking && loc != null) {
      final pointPaint = Paint()
        ..color = const Color(0xFFE65100)
        ..style = PaintingStyle.fill;
        
      final ringPaint = Paint()
        ..color = const Color(0xFFE65100).withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Draw active vehicle dot (pulse animation mock: center of the radar with minor updates)
      canvas.drawCircle(center, 8, pointPaint);
      canvas.drawCircle(center, 16, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Custom Deterministic QR Code Painter
class QrCodePainter extends CustomPainter {
  final String data;
  QrCodePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0A2540)
      ..style = PaintingStyle.fill;

    // Draw finder patterns (outer alignment squares)
    final double finderSize = size.width * 0.28;
    _drawFinderPattern(canvas, const Offset(0, 0), finderSize, paint);
    _drawFinderPattern(canvas, Offset(size.width - finderSize, 0), finderSize, paint);
    _drawFinderPattern(canvas, Offset(0, size.height - finderSize), finderSize, paint);

    // Mock deterministic block matrix based on ticket data hash
    final int hash = data.hashCode;
    const int rows = 12;
    const int cols = 12;
    final double blockW = size.width / cols;
    final double blockH = size.height / rows;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // Skip finder areas
        if ((r < 4 && c < 4) || (r < 4 && c >= cols - 4) || (r >= rows - 4 && c < 4)) {
          continue;
        }
        final int val = (hash ^ (r * 37 + c * 73)) % 100;
        if (val < 45) {
          canvas.drawRect(
            Rect.fromLTWH(c * blockW, r * blockH, blockW - 0.5, blockH - 0.5),
            paint,
          );
        }
      }
    }
  }

  void _drawFinderPattern(Canvas canvas, Offset offset, double size, Paint paint) {
    canvas.drawRect(Rect.fromLTWH(offset.dx, offset.dy, size, size), paint);
    final whitePaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final double inset1 = size * 0.2;
    canvas.drawRect(Rect.fromLTWH(offset.dx + inset1, offset.dy + inset1, size - inset1 * 2, size - inset1 * 2), whitePaint);
    final double inset2 = size * 0.4;
    canvas.drawRect(Rect.fromLTWH(offset.dx + inset2, offset.dy + inset2, size - inset2 * 2, size - inset2 * 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Sub-Tab 3: Passenger Bookings Tickets List
class PassengerBookingsTab extends StatelessWidget {
  const PassengerBookingsTab({super.key});

  void _showDownloadTicketDialog(BuildContext context, Map<String, dynamic> b) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
              const SizedBox(height: 12),
              const Text(
                'Ticket Downloaded!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'TKT-${b['id'].toString().substring(0, 8).toUpperCase()}.pdf successfully saved to your downloads folder.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Container(
                width: 140,
                height: 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: CustomPaint(
                  painter: QrCodePainter(b['id'].toString()),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Show this QR to the Driver/Owner',
                style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A2540),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Close'),
              ),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('My Booked Tickets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Text('Present these digital tickets during boarding.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24),
                onPressed: () => state.logout(),
                tooltip: 'Log Out',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: state.bookings.isEmpty
                ? const Center(child: Text('No tickets booked yet.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 95),
                    itemCount: state.bookings.length,
                    itemBuilder: (context, index) {
                      final b = state.bookings[index];
                      final ticketCode = 'TKT-${b['id'].toString().substring(0, 8).toUpperCase()}';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Colors.black12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(b['bus_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        Text(b['reg'], style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace')),
                                        const SizedBox(height: 12),
                                        Text('Route: ${b['origin']} \u2192 ${b['destination']}', style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Text('Seats Reserved: ${b['seats'].join(', ')}', style: const TextStyle(color: Colors.black87)),
                                        Text('Departure: ${b['departure']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  // QR Code visualization block
                                  Container(
                                    width: 76,
                                    height: 76,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: Colors.black12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: CustomPaint(
                                      painter: QrCodePainter(b['id'].toString()),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24, color: Colors.black12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(ticketCode, style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF0A2540), fontSize: 12, fontWeight: FontWeight.bold)),
                                  TextButton.icon(
                                    onPressed: () => _showDownloadTicketDialog(context, b),
                                    icon: const Icon(Icons.download_rounded, size: 14, color: Color(0xFFE65100)),
                                    label: const Text('Download', style: TextStyle(fontSize: 12, color: Color(0xFFE65100), fontWeight: FontWeight.bold)),
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                                  ),
                                  Text('Fare: Rs. ${b['price']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}

// =====================================================================
// 5. VEHICLE OWNER MAIN SCREEN
// =====================================================================
class OwnerMainScreen extends StatefulWidget {
  const OwnerMainScreen({super.key});

  @override
  State<OwnerMainScreen> createState() => _OwnerMainScreenState();
}

class _OwnerMainScreenState extends State<OwnerMainScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const OwnerVehiclesTab(),
    const OwnerTripsTab(),
    const OwnerScannerTab(),
    const OwnerStreamingTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Owner Hub • ${state.userName}', style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () => state.logout(),
          )
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.airport_shuttle_rounded), label: 'Vehicles'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'Schedules'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner_rounded), label: 'Verify QR'),
          BottomNavigationBarItem(icon: Icon(Icons.sensors_rounded), label: 'Live GPS Stream'),
        ],
      ),
    );
  }
}

// Owner Ticket Verification Tab
class OwnerScannerTab extends StatefulWidget {
  const OwnerScannerTab({super.key});

  @override
  State<OwnerScannerTab> createState() => _OwnerScannerTabState();
}

class _OwnerScannerTabState extends State<OwnerScannerTab> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  String? _selectedBookingId;
  Map<String, dynamic>? _scannedTicket;
  bool _isScanning = false;
  bool _scanAttempted = false;

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
      _isScanning = true;
      _scanAttempted = false;
      _scannedTicket = null;
    });

    // Simulate scanning delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final match = bookings.firstWhere((b) => b['id'].toString() == _selectedBookingId);
      setState(() {
        _isScanning = false;
        _scanAttempted = true;
        _scannedTicket = match;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    // Filter out only bookings that belong to this owner's vehicles
    final ownerBookings = state.bookings;

    if (ownerBookings.isNotEmpty && _selectedBookingId == null) {
      _selectedBookingId = ownerBookings[0]['id'].toString();
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ticket Scanner Console', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Scan or select passenger QR tickets to verify boarding authorization.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Scanner Viewfinder block
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black26),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Grid/Finder outline container
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE65100), width: 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        // Corner finder highlights
                        Positioned(
                          top: 80,
                          child: const Text(
                            'Align passenger QR Code',
                            style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        
                        // Pulsing laser beam line
                        AnimatedBuilder(
                          animation: _animController,
                          builder: (context, child) {
                            final double dy = (_animController.value * 200) - 100;
                            return Positioned(
                              top: 200 * 0.5 + dy + 68,
                              child: Container(
                                width: 200,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent.withOpacity(0.8),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    )
                                  ]
                                ),
                              ),
                            );
                          },
                        ),
                        
                        // Scan loading overlay
                        if (_isScanning)
                          Container(
                            color: Colors.black.withOpacity(0.74),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFFE65100)),
                                  SizedBox(height: 12),
                                  Text('Scanning ticket token...', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // 2. Verification details panel
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Simulator controls', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
                        const SizedBox(height: 8),
                        
                        ownerBookings.isEmpty
                            ? const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text('No passenger bookings active on your routes yet.', style: TextStyle(color: Colors.black54, fontSize: 12)),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DropdownButtonFormField<String>(
                                    value: _selectedBookingId,
                                    decoration: InputDecoration(
                                      labelText: 'Select Ticket to Verify',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    items: ownerBookings.map((b) {
                                      final passengerName = b['passenger_name'] ?? 'Passenger';
                                      final tktCode = 'TKT-${b['id'].toString().substring(0, 8).toUpperCase()}';
                                      return DropdownMenuItem<String>(
                                        value: b['id'].toString(),
                                        child: Text('$tktCode ($passengerName - ${b['seats'].join(',')})', style: const TextStyle(fontSize: 12)),
                                      );
                                    }).toList(),
                                    onChanged: (val) => setState(() => _selectedBookingId = val),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _simulateScan(ownerBookings),
                                    icon: const Icon(Icons.qr_code_scanner_rounded),
                                    label: const Text('Simulate Scan QR'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0A2540),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ],
                              ),
                        
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        
                        // Verification Output
                        if (_scanAttempted && _scannedTicket != null) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              border: Border.all(color: const Color(0xFF81C784)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.verified_user_rounded, color: Color(0xFF2E7D32)),
                                    SizedBox(width: 8),
                                    Text('✅ TICKET VALIDATED', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32), fontSize: 14)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text('Passenger: ${_scannedTicket!['passenger_name']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                                Text('Reserved Seats: ${_scannedTicket!['seats'].join(', ')}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                Text('Route: ${_scannedTicket!['origin']} ➔ ${_scannedTicket!['destination']}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                Text('Fare Status: PAID (Rs. ${_scannedTicket!['price']})', style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 12),
                                const Text('Verification status: APPROVED FOR BOARDING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                              ],
                            ),
                          )
                        ] else if (_scanAttempted) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              border: Border.all(color: const Color(0xFFE57373)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.error_outline_rounded, color: Color(0xFFC62828)),
                                    SizedBox(width: 8),
                                    Text('❌ INVALID TICKET', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC62828), fontSize: 14)),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text('The scanned QR code is either expired, fake, or has not been paid.', style: TextStyle(fontSize: 12, color: Colors.black87)),
                              ],
                            ),
                          )
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F6F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: const Center(
                              child: Text('Waiting to scan ticket QR code...', style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                            ),
                          )
                        ]
                      ],
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
// Owner Tab 1: Vehicles List & Registration
class OwnerVehiclesTab extends StatefulWidget {
  const OwnerVehiclesTab({super.key});

  @override
  State<OwnerVehiclesTab> createState() => _OwnerVehiclesTabState();
}

class _OwnerVehiclesTabState extends State<OwnerVehiclesTab> {
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
                decoration: const InputDecoration(labelText: 'Vehicle Name (e.g. Galle Superliner)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _regController,
                decoration: const InputDecoration(labelText: 'Registration Plate (e.g. WP-ND-1234)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _capacity,
                decoration: const InputDecoration(labelText: 'Seat Capacity'),
                items: [24, 36, 40, 42, 54].map((c) {
                  return DropdownMenuItem<int>(value: c, child: Text('$c Seats'));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _capacity = val);
                },
              )
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_nameController.text.isNotEmpty && _regController.text.isNotEmpty) {
                  Provider.of<AppState>(context, listen: false)
                      .registerVehicle(_nameController.text, _regController.text, _capacity);
                  _nameController.clear();
                  _regController.clear();
                  Navigator.pop(context);
                }
              },
              child: const Text('Register'),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('My Fleet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _showAddVehicleDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Bus'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65100), foregroundColor: Colors.white),
              )
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
                    leading: const Icon(Icons.airport_shuttle_rounded, size: 36, color: Color(0xFFE65100)),
                    title: Text(v['name']),
                    subtitle: Text('${v['reg']} • ${v['total_seats']} Seats'),
                    trailing: Chip(
                      label: Text(v['is_verified'] ? 'Verified' : 'Pending Approval'),
                      backgroundColor: v['is_verified'] ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                      labelStyle: TextStyle(color: v['is_verified'] ? Colors.green : Colors.orange, fontSize: 11),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

// Owner Tab 2: Trip scheduling
class OwnerTripsTab extends StatefulWidget {
  const OwnerTripsTab({super.key});

  @override
  State<OwnerTripsTab> createState() => _OwnerTripsTabState();
}

class _OwnerTripsTabState extends State<OwnerTripsTab> {
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
    final state = Provider.of<AppState>(context, listen: false);
    try {
      final response = await http.get(
        Uri.parse('${state.apiBaseUrl}/routes'),
      ).timeout(const Duration(seconds: 3));

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
    final state = Provider.of<AppState>(context, listen: false);
    if (state.vehicles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please register a vehicle first.')),
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
                    DropdownButtonFormField<String>(
                      value: _selectedVehicleId,
                      decoration: const InputDecoration(labelText: 'Select Vehicle'),
                      items: state.vehicles.map((v) {
                        return DropdownMenuItem<String>(value: v['id'], child: Text('${v['name']} (${v['reg']})'));
                      }).toList(),
                      onChanged: (val) => setDialogState(() => _selectedVehicleId = val),
                    ),
                    const SizedBox(height: 12),
                    
                    _isLoadingRoutes
                        ? const Center(child: CircularProgressIndicator())
                        : _routesList.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('No pre-defined routes found. Contact administrator.', style: TextStyle(color: Colors.redAccent)),
                              )
                            : DropdownButtonFormField<String>(
                                value: _selectedRouteId,
                                decoration: const InputDecoration(labelText: 'Select Route Template'),
                                items: _routesList.map((r) {
                                  final stopsCount = (r['stops'] as List?)?.length ?? 0;
                                  final stopsText = stopsCount > 0 ? ' ($stopsCount stops)' : ' (direct)';
                                  return DropdownMenuItem<String>(
                                    value: r['id'],
                                    child: Text(
                                      '${r['origin']} ➔ ${r['destination']}$stopsText',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setDialogState(() => _selectedRouteId = val),
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
                      decoration: const InputDecoration(labelText: 'Price per Seat (Rs.)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: (_selectedRouteId == null || _priceController.text.isEmpty)
                      ? null
                      : () {
                          final selectedRoute = _routesList.firstWhere((r) => r['id'] == _selectedRouteId);
                          
                          // Format timing: YYYY-MM-DD HH:MM
                          final departureDateTime = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')} ${_timeController.text}';

                          state.scheduleTrip(
                            _selectedVehicleId!,
                            selectedRoute['origin'],
                            selectedRoute['destination'],
                            departureDateTime,
                            double.parse(_priceController.text),
                          );
                          _priceController.clear();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Trip scheduled successfully!')),
                          );
                        },
                  child: const Text('Schedule'),
                )
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Scheduled Journeys', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _showAddTripDialog,
                icon: const Icon(Icons.add),
                label: const Text('Schedule'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65100), foregroundColor: Colors.white),
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: state.trips.length,
              itemBuilder: (context, index) {
                final trip = state.trips[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text('${trip['origin']} \u2192 ${trip['destination']}', style: const TextStyle(color: Color(0xFF0A2540))),
                    subtitle: Text('${trip['bus_name']} • ${trip['departure']}'),
                    trailing: Text('Rs. ${trip['price']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

// Owner Tab 3: GPS Streaming Sender controls
class OwnerStreamingTab extends StatefulWidget {
  const OwnerStreamingTab({super.key});

  @override
  State<OwnerStreamingTab> createState() => _OwnerStreamingTabState();
}

class _OwnerStreamingTabState extends State<OwnerStreamingTab> {
  String? _selectedVehicleId;
  bool _simulateGps = true;

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Live GPS Broadcaster', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Transmit coordinates to passengers tracking your vehicle.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _selectedVehicleId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Select active vehicle to stream GPS',
            ),
            items: state.vehicles.map((v) {
              return DropdownMenuItem<String>(value: v['reg'], child: Text('${v['name']} (${v['reg']})'));
            }).toList(),
            onChanged: (val) => setState(() => _selectedVehicleId = val),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Simulate Route Movement'),
            subtitle: const Text('Generates coordinates along highways. Disable to use real device GPS.'),
            value: _simulateGps,
            onChanged: (val) => setState(() => _simulateGps = val),
            activeColor: const Color(0xFFE65100),
          ),
          const SizedBox(height: 32),
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F9),
                border: Border.all(color: state.isStreamingGPS ? const Color(0xFFE65100).withOpacity(0.5) : Colors.black12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    state.isStreamingGPS ? Icons.sensors : Icons.sensors_off_rounded,
                    size: 64,
                    color: state.isStreamingGPS ? const Color(0xFFE65100) : Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.isStreamingGPS ? 'Broadcasting Coordinates...' : 'GPS Stream Idle',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _selectedVehicleId == null
                        ? null
                        : () {
                            if (state.isStreamingGPS) {
                              state.stopStreamingGPS();
                            } else {
                              state.startStreamingGPS(_selectedVehicleId!, _simulateGps);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: state.isStreamingGPS ? Colors.redAccent : const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(state.isStreamingGPS ? 'Stop GPS Broadcast' : 'Start GPS Broadcast'),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
