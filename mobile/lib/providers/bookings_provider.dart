import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/providers/auth_provider.dart';
import 'package:seaty/utils/sri_lanka_time.dart';

class BookingsState {
  final List<Map<String, dynamic>> bookings;
  final List<String> selectedSeats;
  final Map<String, String> selectedSeatGenders;
  final List<String> bookedSeats;
  final List<String> heldSeats;
  final Map<String, String> seatGenders;

  BookingsState({
    required this.bookings,
    required this.selectedSeats,
    required this.selectedSeatGenders,
    required this.bookedSeats,
    required this.heldSeats,
    required this.seatGenders,
  });

  BookingsState copyWith({
    List<Map<String, dynamic>>? bookings,
    List<String>? selectedSeats,
    Map<String, String>? selectedSeatGenders,
    List<String>? bookedSeats,
    List<String>? heldSeats,
    Map<String, String>? seatGenders,
  }) {
    return BookingsState(
      bookings: bookings ?? this.bookings,
      selectedSeats: selectedSeats ?? this.selectedSeats,
      selectedSeatGenders: selectedSeatGenders ?? this.selectedSeatGenders,
      bookedSeats: bookedSeats ?? this.bookedSeats,
      heldSeats: heldSeats ?? this.heldSeats,
      seatGenders: seatGenders ?? this.seatGenders,
    );
  }
}

class BookingsNotifier extends Notifier<BookingsState> {
  @override
  BookingsState build() {
    final auth = ref.watch(authProvider);

    if (auth.isAuthenticated) {
      Future.microtask(() => loadBookings());
    }

    return BookingsState(
      bookings: [],
      selectedSeats: [],
      selectedSeatGenders: {},
      bookedSeats: [],
      heldSeats: [],
      seatGenders: {},
    );
  }

  Future<void> loadBookings() async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) return;
    final settings = ref.read(settingsProvider);

    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/bookings'),
            headers: {'Authorization': 'Bearer ${auth.token}'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> loadedBookings = [];
        for (var item in data) {
          final b = item as Map<String, dynamic>;
          final trip = b['trip'] ?? {};
          final vehicle = trip['vehicle'] ?? {};
          final conductor = trip['conductor'] ?? {};
          final conductorPhone = (conductor['phone_number'] ?? vehicle['contact_phone'] ?? 'N/A').toString();
          loadedBookings.add({
            'id': b['id'],
            'trip_id': b['trip_id'],
            'origin': trip['route']?['origin'] ?? 'Colombo Fort',
            'destination': trip['route']?['destination'] ?? 'Galle',
            'departure':
                isoToSriLankaWallClock(trip['departure_time']) ??
                '2026-07-13 14:00',
            'arrival': isoToSriLankaWallClock(trip['arrival_time']) ?? '',
            'stops': trip['route']?['stops'] ?? [],
            'bus_name': vehicle['name'] ?? 'Luxury Express',
            'reg': vehicle['registration_number'] ?? 'WP-ND-0000',
            'seats': List<String>.from(b['selected_seats'] ?? []),
            'price': double.tryParse(b['total_price'].toString()) ?? 0.0,
            'platform_fee': double.tryParse(b['platform_fee']?.toString() ?? '0.0') ?? 25.0,
            'status': b['booking_status'] ?? 'pending',
            'payment_status': b['payment_status'] ?? 'pending',
            'conductor_phone': conductorPhone,
            'passenger_name': b['passenger']?['full_name'] ?? 'Passenger',
            'boarded_seats': List<String>.from(trip['boarded_seats'] ?? []),
            'passenger_details': b['passenger_details'] ?? {},
          });
        }
        state = state.copyWith(bookings: loadedBookings);
      } else if (response.statusCode == 401) {
        await ref.read(authProvider.notifier).logout();
      }
    } catch (e) {
      debugPrint('Error loading bookings: $e');
    }
  }

  Future<void> loadSeatAvailability(String tripId, {bool clearFirst = false}) async {
    if (clearFirst) {
      state = state.copyWith(
        bookedSeats: [],
        heldSeats: [],
        seatGenders: {},
      );
    }
    final settings = ref.read(settingsProvider);

    try {
      final response = await http
          .get(Uri.parse('${settings.apiBaseUrl}/seat-holds/trip/$tripId'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        Map<String, String> genders = {};
        if (data['seat_genders'] != null) {
          genders = Map<String, String>.from(data['seat_genders']);
        }
        state = state.copyWith(
          bookedSeats: List<String>.from(data['booked_seats'] ?? []),
          heldSeats: List<String>.from(data['held_seats'] ?? []),
          seatGenders: genders,
        );
      }
    } catch (e) {
      debugPrint('Error loading seat availability: $e');
    }
  }

  void selectSeatWithGender(String seatLabel, String gender) {
    final List<String> currentSelected = [...state.selectedSeats];
    if (!currentSelected.contains(seatLabel)) {
      if (currentSelected.length >= 6) return;
      currentSelected.add(seatLabel);
    }
    final Map<String, String> currentGenders = {...state.selectedSeatGenders};
    currentGenders[seatLabel] = gender;

    state = state.copyWith(
      selectedSeats: currentSelected,
      selectedSeatGenders: currentGenders,
    );
  }

  void deselectSeat(String seatLabel) {
    final List<String> currentSelected = [...state.selectedSeats]..remove(seatLabel);
    final Map<String, String> currentGenders = {...state.selectedSeatGenders}..remove(seatLabel);

    state = state.copyWith(
      selectedSeats: currentSelected,
      selectedSeatGenders: currentGenders,
    );
  }

  void clearSelectedSeats() {
    state = state.copyWith(
      selectedSeats: [],
      selectedSeatGenders: {},
    );
  }

  /// Detail of the most recent failed booking/payment call, so the UI can show
  /// the server's actual reason (e.g. the 30-minute pre-departure cutoff)
  /// instead of a generic message. Null when the last call succeeded.
  String? lastErrorMessage;

  /// Pulls FastAPI's `detail` out of an error body. Falls back to null so
  /// callers keep their existing generic copy when the shape is unexpected.
  String? _extractErrorDetail(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['detail'] != null) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) return detail;
        // Pydantic validation errors arrive as a list of maps.
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] != null) return first['msg'].toString();
        }
      }
    } catch (_) {
      // Non-JSON body - nothing useful to surface.
    }
    return null;
  }

  Future<Map<String, dynamic>?> initiateBooking(
    String tripId,
    Map<String, dynamic> passengerDetails,
  ) async {
    if (state.selectedSeats.isEmpty) return null;
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final response = await http.post(
        Uri.parse('${settings.apiBaseUrl}/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
        },
        body: json.encode({
          'trip_id': tripId,
          'selected_seats': state.selectedSeats,
          'passenger_details': passengerDetails,
        }),
      );

      if (response.statusCode == 201) {
        lastErrorMessage = null;
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        await ref.read(authProvider.notifier).logout();
      } else {
        lastErrorMessage = _extractErrorDetail(response.body);
      }
    } catch (e) {
      debugPrint('Error initiating booking: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> initiatePayment(String bookingId) async {
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final response = await http.post(
        Uri.parse('${settings.apiBaseUrl}/payments/initiate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
        },
        body: json.encode({'booking_id': bookingId}),
      );

      if (response.statusCode == 201) {
        lastErrorMessage = null;
        return json.decode(response.body);
      } else {
        lastErrorMessage = _extractErrorDetail(response.body);
      }
    } catch (e) {
      debugPrint('Error initiating payment: $e');
    }
    return null;
  }


  Future<List<String>?> toggleBoarding(String tripId, String seat, {String? action}) async {
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final queryParams = action != null ? '?seat=$seat&action=$action' : '?seat=$seat';
      final response = await http
          .post(
            Uri.parse('${settings.apiBaseUrl}/trips/$tripId/toggle-board$queryParams'),
            headers: {'Authorization': 'Bearer ${auth.token}'},
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

  Future<Map<String, dynamic>?> fetchTripManifest(String tripId) async {
    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/trips/$tripId/manifest'),
            headers: {'Authorization': 'Bearer ${auth.token}'},
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

  Future<Map<String, dynamic>?> fetchBookingDetails(String bookingId) async {
    final auth = ref.read(authProvider);
    if (auth.token.isEmpty || auth.token.startsWith('simulated')) {
      try {
        final b = state.bookings.firstWhere(
          (item) => item['id'].toString().toLowerCase() == bookingId.toLowerCase(),
        );
        return b;
      } catch (e) {
        return null;
      }
    }

    final settings = ref.read(settingsProvider);
    try {
      final response = await http
          .get(
            Uri.parse('${settings.apiBaseUrl}/bookings/$bookingId'),
            headers: {'Authorization': 'Bearer ${auth.token}'},
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
              isoToSriLankaWallClock(trip['departure_time']) ??
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

  void bookTicket(Map<String, dynamic> trip) {
    if (state.selectedSeats.isEmpty) return;

    final newBooking = {
      'id': 'b-${DateTime.now().millisecondsSinceEpoch}',
      'trip_id': trip['id'],
      'origin': trip['origin'],
      'destination': trip['destination'],
      'departure': trip['departure'],
      'bus_name': trip['bus_name'],
      'reg': trip['reg'],
      'seats': List<String>.from(state.selectedSeats),
      'price': trip['price'] * state.selectedSeats.length,
      'status': 'confirmed',
    };

    state = state.copyWith(
      bookings: [newBooking, ...state.bookings],
      selectedSeats: [],
      selectedSeatGenders: {},
    );
  }

  void addHeldSeats(List<String> seats) {
    state = state.copyWith(heldSeats: [...state.heldSeats, ...seats]);
  }

  void addBookedSeats(List<String> seats) {
    state = state.copyWith(bookedSeats: [...state.bookedSeats, ...seats]);
  }

  void releaseSeats(List<String> seats) {
    final List<String> newHeld = [...state.heldSeats]..removeWhere((s) => seats.contains(s));
    final List<String> newBooked = [...state.bookedSeats]..removeWhere((s) => seats.contains(s));
    state = state.copyWith(heldSeats: newHeld, bookedSeats: newBooked);
  }
}

final bookingsProvider = NotifierProvider<BookingsNotifier, BookingsState>(() => BookingsNotifier());
