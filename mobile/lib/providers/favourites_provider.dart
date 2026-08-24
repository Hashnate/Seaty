import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/providers/auth_provider.dart';

class FavouritesState {
  final Set<String> favouriteVehicleIds;
  final Set<String> favouriteScheduleIds;
  final bool isLoading;

  FavouritesState({
    required this.favouriteVehicleIds,
    required this.favouriteScheduleIds,
    this.isLoading = false,
  });

  FavouritesState copyWith({
    Set<String>? favouriteVehicleIds,
    Set<String>? favouriteScheduleIds,
    bool? isLoading,
  }) {
    return FavouritesState(
      favouriteVehicleIds: favouriteVehicleIds ?? this.favouriteVehicleIds,
      favouriteScheduleIds: favouriteScheduleIds ?? this.favouriteScheduleIds,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool isFavourite({String? vehicleId, String? scheduleId}) {
    if (scheduleId != null && scheduleId.isNotEmpty && favouriteScheduleIds.contains(scheduleId)) {
      return true;
    }
    if (vehicleId != null && vehicleId.isNotEmpty && favouriteVehicleIds.contains(vehicleId)) {
      return true;
    }
    return false;
  }
}

class FavouritesNotifier extends Notifier<FavouritesState> {
  @override
  FavouritesState build() {
    final session = ref.watch(sessionProvider);

    if (session.isAuthenticated) {
      Future.microtask(() => loadFavourites());
    }

    return FavouritesState(
      favouriteVehicleIds: {},
      favouriteScheduleIds: {},
    );
  }

  Future<void> loadFavourites() async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) return;
    final settings = ref.read(settingsProvider);

    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/favourites/ids'),
            headers: {'Authorization': 'Bearer ${auth.token}'},
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List vIds = data['vehicle_ids'] ?? [];
        final List sIds = data['schedule_ids'] ?? [];
        state = state.copyWith(
          favouriteVehicleIds: Set<String>.from(vIds.map((e) => e.toString())),
          favouriteScheduleIds: Set<String>.from(sIds.map((e) => e.toString())),
        );
      }
    } catch (e) {
      debugPrint('Error loading favourites: $e');
    }
  }

  Future<bool> toggleFavourite({required String vehicleId, String? scheduleId}) async {
    final auth = ref.read(authProvider);
    final isFav = state.isFavourite(vehicleId: vehicleId, scheduleId: scheduleId);

    // Optimistic UI update
    final newV = Set<String>.from(state.favouriteVehicleIds);
    final newS = Set<String>.from(state.favouriteScheduleIds);

    if (isFav) {
      newV.remove(vehicleId);
      if (scheduleId != null) newS.remove(scheduleId);
    } else {
      newV.add(vehicleId);
      if (scheduleId != null) newS.add(scheduleId);
    }

    state = state.copyWith(favouriteVehicleIds: newV, favouriteScheduleIds: newS);

    if (auth.token.isEmpty || auth.token.startsWith('simulated')) {
      return !isFav;
    }

    final settings = ref.read(settingsProvider);
    try {
      final bodyMap = <String, dynamic>{'vehicle_id': vehicleId};
      if (scheduleId != null && scheduleId.isNotEmpty) {
        bodyMap['schedule_id'] = scheduleId;
      }

      final response = await http.post(
        Uri.parse('${settings.apiBaseUrl}/favourites/toggle'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
        },
        body: json.encode(bodyMap),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['favourited'] == true;
      }
    } catch (e) {
      debugPrint('Error toggling favourite: $e');
    }
    return !isFav;
  }
}

final favouritesProvider = NotifierProvider<FavouritesNotifier, FavouritesState>(
  () => FavouritesNotifier(),
);
