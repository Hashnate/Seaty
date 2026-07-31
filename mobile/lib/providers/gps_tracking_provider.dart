import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/providers/auth_provider.dart';

class GpsTrackingState {
  final Map<String, dynamic>? trackedBusLocation;
  final bool isTracking;
  final bool isStreamingGPS;

  GpsTrackingState({
    this.trackedBusLocation,
    required this.isTracking,
    required this.isStreamingGPS,
  });

  GpsTrackingState copyWith({
    Map<String, dynamic>? trackedBusLocation,
    bool? isTracking,
    bool? isStreamingGPS,
    bool clearTrackedLocation = false,
  }) {
    return GpsTrackingState(
      trackedBusLocation: clearTrackedLocation ? null : (trackedBusLocation ?? this.trackedBusLocation),
      isTracking: isTracking ?? this.isTracking,
      isStreamingGPS: isStreamingGPS ?? this.isStreamingGPS,
    );
  }
}

class GpsTrackingNotifier extends Notifier<GpsTrackingState> {
  WebSocketChannel? _trackingChannel;
  Timer? _trackingTimer;

  WebSocketChannel? _streamingChannel;
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  GpsTrackingState build() {
    ref.onDispose(() {
      _cleanup();
    });

    return GpsTrackingState(
      trackedBusLocation: null,
      isTracking: false,
      isStreamingGPS: false,
    );
  }

  void _cleanup() {
    _trackingChannel?.sink.close();
    _trackingTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _streamingChannel?.sink.close();
  }

  void startTracking(String vehicleId) {
    stopTracking();
    state = state.copyWith(isTracking: true, clearTrackedLocation: true);

    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final wsUrl = '${settings.wsBaseUrl}/tracking/$vehicleId?role=passenger&token=${auth.token}';
      _trackingChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _trackingChannel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message);
            state = state.copyWith(trackedBusLocation: data);
          } catch (e) {
            debugPrint('Error parsing tracking message: $e');
          }
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
      debugPrint('WebSocket connection failed: $e.');
      stopTracking();
    }
  }

  void stopTracking() {
    _trackingChannel?.sink.close();
    _trackingChannel = null;
    _trackingTimer?.cancel();
    _trackingTimer = null;

    state = state.copyWith(isTracking: false, clearTrackedLocation: true);
  }

  Future<void> startStreamingGPS(String vehicleId, bool simulate) async {
    stopStreamingGPS();
    state = state.copyWith(isStreamingGPS: true);

    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider);

    try {
      final wsUrl = '${settings.wsBaseUrl}/tracking/$vehicleId?role=driver&token=${auth.token}';
      _streamingChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    } catch (e) {
      debugPrint('Streaming socket connection failed: $e');
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      state = state.copyWith(isStreamingGPS: false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        state = state.copyWith(isStreamingGPS: false);
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
        'heading': position.heading,
      };

      _streamingChannel?.sink.add(json.encode(payload));
    });
  }

  void stopStreamingGPS() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _streamingChannel?.sink.close();
    _streamingChannel = null;

    state = state.copyWith(isStreamingGPS: false);
  }
}

final gpsTrackingProvider = NotifierProvider<GpsTrackingNotifier, GpsTrackingState>(() => GpsTrackingNotifier());
