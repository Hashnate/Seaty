import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/providers/auth_provider.dart';
import 'package:seaty/utils/sri_lanka_time.dart';

/// Trips the signed-in passenger holds a ticket for that are trackable now.
///
/// Deliberately separate from [tripsProvider]: that one backs home-screen
/// search, which must keep hiding buses departing within 30 minutes because
/// they can no longer be booked. The tracker needs exactly those buses, so it
/// reads this instead - sharing one list would force search to show a bus the
/// passenger can't book.
class ActiveTripsState {
  final List<Map<String, dynamic>> trips;
  final bool isLoading;

  const ActiveTripsState({this.trips = const [], this.isLoading = false});

  ActiveTripsState copyWith({List<Map<String, dynamic>>? trips, bool? isLoading}) {
    return ActiveTripsState(
      trips: trips ?? this.trips,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ActiveTripsNotifier extends Notifier<ActiveTripsState> {
  @override
  ActiveTripsState build() {
    Future.microtask(loadActiveTrips);
    return const ActiveTripsState(isLoading: true);
  }

  Future<void> loadActiveTrips() async {
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    if (auth.token.isEmpty || auth.token.startsWith('simulated')) {
      state = const ActiveTripsState(trips: [], isLoading: false);
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/trips/my-active'),
            headers: {'Authorization': 'Bearer ${auth.token}'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final loaded = <Map<String, dynamic>>[];
        for (final item in data) {
          if (item is! Map<String, dynamic>) continue;
          final vehicle = item['vehicle'] ?? {};
          loaded.add({
            'id': item['id'],
            'vehicle_id': vehicle['id'] ?? item['vehicle_id'],
            'origin': item['route']?['origin'] ?? '',
            'destination': item['route']?['destination'] ?? '',
            'route': item['route'],
            'departure': isoToSriLankaWallClock(item['departure_time']) ?? '',
            'arrival': isoToSriLankaWallClock(item['arrival_time']) ?? '',
            'bus_name': vehicle['name'] ?? 'Bus',
            'reg': vehicle['registration_number'] ?? '',
            'total_seats': vehicle['total_seats'] ?? 40,
            'boarded_seats': List<String>.from(item['boarded_seats'] ?? []),
          });
        }
        state = ActiveTripsState(trips: loaded, isLoading: false);
        return;
      }
    } catch (e) {
      debugPrint('Error loading active trips: $e');
    }

    state = state.copyWith(isLoading: false);
  }
}

final activeTripsProvider =
    NotifierProvider<ActiveTripsNotifier, ActiveTripsState>(() => ActiveTripsNotifier());
