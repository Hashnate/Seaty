import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/providers/auth_provider.dart';

class FleetState {
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> conductors;

  FleetState({required this.vehicles, required this.conductors});

  FleetState copyWith({
    List<Map<String, dynamic>>? vehicles,
    List<Map<String, dynamic>>? conductors,
  }) {
    return FleetState(
      vehicles: vehicles ?? this.vehicles,
      conductors: conductors ?? this.conductors,
    );
  }
}

class FleetNotifier extends Notifier<FleetState> {
  @override
  FleetState build() {
    final auth = ref.watch(authProvider);

    // Initial local fallback vehicles
    final initialVehicles = [
      {
        'id': 'v-deluxe',
        'name': 'Colombo Express VIP',
        'reg': 'WP-ND-8942',
        'total_seats': 40,
        'is_verified': true,
      },
    ];

    final List<Map<String, dynamic>> savedConductorsList = [];
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedConductors = prefs.getString('conductors_json');
    if (savedConductors != null && savedConductors.isNotEmpty) {
      try {
        final List<dynamic> list = json.decode(savedConductors);
        for (var item in list) {
          if (item is Map<String, dynamic>) {
            final norm = normalizePhone((item['phone_number'] ?? '').toString());
            if (!savedConductorsList.any(
              (c) => normalizePhone((c['phone_number'] ?? '').toString()) == norm,
            )) {
              savedConductorsList.add(item);
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading saved conductors: $e');
      }
    }

    if (auth.isAuthenticated) {
      Future.microtask(() {
        loadVehicles();
        loadConductors();
      });
    }

    return FleetState(
      vehicles: initialVehicles,
      conductors: savedConductorsList,
    );
  }

  void _saveConductorsToPrefs(List<Map<String, dynamic>> conductors) {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setString('conductors_json', json.encode(conductors));
    } catch (e) {
      debugPrint('Error saving conductors to prefs: $e');
    }
  }

  Future<void> loadVehicles() async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) return;
    final settings = ref.read(settingsProvider);

    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/vehicles'),
            headers: {'Authorization': 'Bearer ${auth.token}'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> loadedVehicles = [];
        for (var item in data) {
          loadedVehicles.add(item as Map<String, dynamic>);
        }
        state = state.copyWith(vehicles: loadedVehicles);
      } else if (response.statusCode == 401) {
        ref.read(authProvider.notifier).logout();
      }
    } catch (e) {
      debugPrint('Error loading vehicles: $e');
    }
  }

  Future<void> loadConductors() async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) return;
    final settings = ref.read(settingsProvider);

    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/conductors'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${auth.token}',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> loadedConductors = [];
        for (var item in data) {
          if (item is Map<String, dynamic>) {
            loadedConductors.add(item);
          }
        }
        _saveConductorsToPrefs(loadedConductors);
        state = state.copyWith(conductors: loadedConductors);
      }
    } catch (e) {
      debugPrint('Error loading conductors: $e');
    }
  }

  Future<Map<String, dynamic>?> addConductor(String name, String phone) async {
    final auth = ref.read(authProvider);
    final settings = ref.read(settingsProvider);

    final newConductor = {
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'full_name': name,
      'phone_number': phone,
      'role': 'conductor',
    };

    final List<Map<String, dynamic>> tempConductors = [...state.conductors, newConductor];
    state = state.copyWith(conductors: tempConductors);
    _saveConductorsToPrefs(tempConductors);

    try {
      final response = await http
          .post(
            Uri.parse('${settings.apiBaseUrl}/conductors'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${auth.token}',
            },
            body: json.encode({'full_name': name, 'phone_number': phone}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final List<Map<String, dynamic>> updatedConductors = [...state.conductors]
          ..removeWhere((c) => c['id'].toString() == newConductor['id'])
          ..add(data);

        state = state.copyWith(conductors: updatedConductors);
        _saveConductorsToPrefs(updatedConductors);
        return data;
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['detail'] ?? 'Failed to add conductor');
      }
    } catch (e) {
      final List<Map<String, dynamic>> updatedConductors = [...state.conductors]
        ..removeWhere((c) => c['id'].toString() == newConductor['id']);

      state = state.copyWith(conductors: updatedConductors);
      _saveConductorsToPrefs(updatedConductors);
      debugPrint('Error adding conductor: $e');
      rethrow;
    }
  }

  Future<bool> deleteConductor(String conductorId) async {
    final auth = ref.read(authProvider);
    final settings = ref.read(settingsProvider);

    if (auth.token.isEmpty || auth.token.startsWith('simulated')) {
      final List<Map<String, dynamic>> updated = [...state.conductors]
        ..removeWhere((c) => c['id'].toString() == conductorId);
      state = state.copyWith(conductors: updated);
      _saveConductorsToPrefs(updated);
      return true;
    }
    try {
      final response = await http
          .delete(
            Uri.parse('${settings.apiBaseUrl}/conductors/$conductorId'),
            headers: {'Authorization': 'Bearer ${auth.token}'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 204 || response.statusCode == 200) {
        final List<Map<String, dynamic>> updated = [...state.conductors]
          ..removeWhere((c) => c['id'].toString() == conductorId);
        state = state.copyWith(conductors: updated);
        _saveConductorsToPrefs(updated);
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting conductor: $e');
    }
    return false;
  }

  void registerVehicle(String name, String reg, int capacity) async {
    final auth = ref.read(authProvider);
    final settings = ref.read(settingsProvider);

    try {
      final response = await http.post(
        Uri.parse('${settings.apiBaseUrl}/vehicles'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
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
    final newVehicle = {
      'id': 'v-${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'reg': reg,
      'total_seats': capacity,
      'is_verified': false,
    };
    state = state.copyWith(vehicles: [...state.vehicles, newVehicle]);
  }

  Future<Map<String, dynamic>> fetchVehicleReviews(String vehicleId) async {
    if (vehicleId.isEmpty) {
      return {'average_rating': 0.0, 'total_reviews': 0, 'reviews': []};
    }
    final settings = ref.read(settingsProvider);

    try {
      final response = await http
          .get(Uri.parse('${settings.apiBaseUrl}/vehicles/$vehicleId/reviews'))
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
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (auth.token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${auth.token}';
      }
      final response = await http
          .post(
            Uri.parse('${settings.apiBaseUrl}/vehicles/$vehicleId/reviews'),
            headers: headers,
            body: json.encode({
              'rating': rating,
              'comment': comment,
              'passenger_name': auth.userName.isNotEmpty ? auth.userName : 'Passenger',
            }),
          )
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('Error submitting review: $e');
      return false;
    }
  }
}

final fleetProvider = NotifierProvider<FleetNotifier, FleetState>(() => FleetNotifier());
