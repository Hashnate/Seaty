import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/providers/auth_provider.dart';

class TripsState {
  final List<Map<String, dynamic>> trips;
  final String selectedFrom;
  final String selectedTo;
  final DateTime? selectedDate;

  TripsState({
    required this.trips,
    required this.selectedFrom,
    required this.selectedTo,
    this.selectedDate,
  });

  TripsState copyWith({
    List<Map<String, dynamic>>? trips,
    String? selectedFrom,
    String? selectedTo,
    DateTime? selectedDate,
  }) {
    return TripsState(
      trips: trips ?? this.trips,
      selectedFrom: selectedFrom ?? this.selectedFrom,
      selectedTo: selectedTo ?? this.selectedTo,
      selectedDate: selectedDate ?? this.selectedDate,
    );
  }
}

class TripsNotifier extends Notifier<TripsState> {
  @override
  TripsState build() {
    // Initial local fallback trips
    final initialTrips = [
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

    // Read initial data in the background
    Future.microtask(() => loadTrips());

    return TripsState(
      trips: initialTrips,
      selectedFrom: '',
      selectedTo: '',
    );
  }

  void updateSearchFilter(String from, String to, DateTime? date) {
    state = state.copyWith(
      selectedFrom: from,
      selectedTo: to,
      selectedDate: date,
    );
  }

  Future<void> loadTrips({String? date}) async {
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final Map<String, String> headers = {};
      if (auth.token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${auth.token}';
      }

      final queryDate = date ??
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      final response = await http
          .get(Uri.parse('${settings.apiBaseUrl}/trips?date=$queryDate'), headers: headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> loadedTrips = [];
        for (var item in data) {
          final tripMap = item as Map<String, dynamic>;
          final vehicle = tripMap['vehicle'] ?? {};
          loadedTrips.add({
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
        state = state.copyWith(trips: loadedTrips);
      }
    } catch (e) {
      debugPrint('Error loading trips: $e');
    }
  }

  void scheduleTrip(
    String vehicleId,
    String origin,
    String destination,
    String time,
    double price,
    List<Map<String, dynamic>> vehicles,
  ) async {
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final v = vehicles.firstWhere(
        (x) => x['id'] == vehicleId || x['reg'] == vehicleId,
        orElse: () => vehicles.isNotEmpty ? vehicles[0] : <String, dynamic>{},
      );

      final routeResponse = await http.post(
        Uri.parse('${settings.apiBaseUrl}/routes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
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
          Uri.parse('${settings.apiBaseUrl}/trips'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${auth.token}',
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
    final v = vehicles.firstWhere(
      (x) => x['id'] == vehicleId || x['reg'] == vehicleId,
      orElse: () => vehicles.isNotEmpty
          ? vehicles[0]
          : {'name': 'Luxury Express', 'reg': 'WP-ND-0000'},
    );
    final newTrip = {
      'id': 't-${DateTime.now().millisecondsSinceEpoch}',
      'origin': origin,
      'destination': destination,
      'departure': time,
      'price': price,
      'bus_name': v['name'] ?? 'Luxury Express',
      'reg': v['reg'] ?? 'WP-ND-0000',
      'amenities': List<String>.from(
        v['amenities'] ?? ['AC', 'WiFi', 'Charging Ports', 'Reclining Seats'],
      ),
    };
    state = state.copyWith(trips: [...state.trips, newTrip]);
  }
}

final tripsProvider = NotifierProvider<TripsNotifier, TripsState>(() => TripsNotifier());
