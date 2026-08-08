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
  final bool isReconnecting;
  final DateTime? lastUpdateAt;

  GpsTrackingState({
    this.trackedBusLocation,
    required this.isTracking,
    required this.isStreamingGPS,
    this.isReconnecting = false,
    this.lastUpdateAt,
  });

  GpsTrackingState copyWith({
    Map<String, dynamic>? trackedBusLocation,
    bool? isTracking,
    bool? isStreamingGPS,
    bool? isReconnecting,
    DateTime? lastUpdateAt,
    bool clearTrackedLocation = false,
    bool clearLastUpdate = false,
  }) {
    return GpsTrackingState(
      trackedBusLocation: clearTrackedLocation ? null : (trackedBusLocation ?? this.trackedBusLocation),
      isTracking: isTracking ?? this.isTracking,
      isStreamingGPS: isStreamingGPS ?? this.isStreamingGPS,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      lastUpdateAt: clearLastUpdate ? null : (lastUpdateAt ?? this.lastUpdateAt),
    );
  }
}

class GpsTrackingNotifier extends Notifier<GpsTrackingState> {
  // Backoff schedule shared by both sockets: 1s, 2s, 4s, 8s, 15s, then 30s forever.
  static const List<int> _reconnectDelaysSeconds = [1, 2, 4, 8, 15, 30];

  // Passenger (listening) side
  WebSocketChannel? _trackingChannel;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _trackedVehicleId;
  bool _passengerManualStop = true;

  // Driver (broadcasting) side
  WebSocketChannel? _streamingChannel;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _streamReconnectTimer;
  int _streamReconnectAttempts = 0;
  String? _streamingVehicleId;
  bool _streamManualStop = true;
  Timer? _heartbeatTimer;
  Position? _lastKnownPosition;

  @override
  GpsTrackingState build() {
    ref.onDispose(_cleanup);

    return GpsTrackingState(
      trackedBusLocation: null,
      isTracking: false,
      isStreamingGPS: false,
      isReconnecting: false,
      lastUpdateAt: null,
    );
  }

  void _cleanup() {
    _trackingChannel?.sink.close();
    _reconnectTimer?.cancel();
    _streamReconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _streamingChannel?.sink.close();
  }

  // =====================================================================
  // Passenger side: listen for a vehicle's broadcast location
  // =====================================================================
  void startTracking(String vehicleId) {
    _passengerManualStop = false;
    _trackedVehicleId = vehicleId;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();

    state = state.copyWith(
      isTracking: true,
      isReconnecting: false,
      clearTrackedLocation: true,
      clearLastUpdate: true,
    );

    _connectPassengerSocket(vehicleId);
  }

  void _connectPassengerSocket(String vehicleId) {
    _trackingChannel?.sink.close();

    try {
      final settings = ref.read(settingsProvider);
      final auth = ref.read(authProvider);
      final wsUrl = '${settings.wsBaseUrl}/tracking/$vehicleId?role=passenger&token=${auth.token}';
      _trackingChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _trackingChannel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message);
            _reconnectAttempts = 0;
            state = state.copyWith(
              trackedBusLocation: data,
              isReconnecting: false,
              lastUpdateAt: DateTime.now(),
            );
          } catch (e) {
            debugPrint('Error parsing tracking message: $e');
          }
        },
        onError: (err) {
          debugPrint('Tracking socket error: $err');
          _scheduleReconnect(vehicleId);
        },
        onDone: () {
          _scheduleReconnect(vehicleId);
        },
      );
    } catch (e) {
      debugPrint('WebSocket connection failed: $e.');
      _scheduleReconnect(vehicleId);
    }
  }

  void _scheduleReconnect(String vehicleId) {
    // Ignore drops from a stale socket (user already switched buses / stopped tracking).
    if (_passengerManualStop || _trackedVehicleId != vehicleId) return;

    _reconnectTimer?.cancel();
    state = state.copyWith(isReconnecting: true);

    final delay = _reconnectDelaysSeconds[_reconnectAttempts.clamp(0, _reconnectDelaysSeconds.length - 1)];
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_passengerManualStop && _trackedVehicleId == vehicleId) {
        _connectPassengerSocket(vehicleId);
      }
    });
  }

  void stopTracking() {
    _passengerManualStop = true;
    _trackedVehicleId = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _trackingChannel?.sink.close();
    _trackingChannel = null;

    state = state.copyWith(
      isTracking: false,
      isReconnecting: false,
      clearTrackedLocation: true,
      clearLastUpdate: true,
    );
  }

  // =====================================================================
  // Driver side: read device GPS and broadcast it
  // =====================================================================
  Future<void> startStreamingGPS(String vehicleId, bool simulate) async {
    stopStreamingGPS();
    _streamManualStop = false;
    _streamingVehicleId = vehicleId;
    _streamReconnectAttempts = 0;
    state = state.copyWith(isStreamingGPS: true);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
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

    _connectStreamingSocket(vehicleId);

    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Seaty trip in progress',
          notificationText: 'Sharing this bus\'s live location with passengers.',
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _lastKnownPosition = position;
      _sendPosition(position);
    });

    // Distance-filtered GPS goes silent while the bus is stationary (traffic, a stop).
    // Resend the last known fix on an interval so passengers can tell "not moving"
    // from "connection lost".
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final last = _lastKnownPosition;
      if (last != null) {
        _sendPosition(last);
      }
    });
  }

  void _sendPosition(Position position) {
    final payload = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'speed': position.speed * 3.6, // m/s to km/h
      'heading': position.heading,
    };
    _streamingChannel?.sink.add(json.encode(payload));
  }

  void _connectStreamingSocket(String vehicleId) {
    _streamingChannel?.sink.close();

    try {
      final settings = ref.read(settingsProvider);
      final auth = ref.read(authProvider);
      final wsUrl = '${settings.wsBaseUrl}/tracking/$vehicleId?role=driver&token=${auth.token}';
      _streamingChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _streamingChannel!.stream.listen(
        (_) {},
        onError: (err) {
          debugPrint('Streaming socket error: $err');
          _scheduleStreamReconnect(vehicleId);
        },
        onDone: () {
          _scheduleStreamReconnect(vehicleId);
        },
      );
    } catch (e) {
      debugPrint('Streaming socket connection failed: $e');
      _scheduleStreamReconnect(vehicleId);
    }
  }

  void _scheduleStreamReconnect(String vehicleId) {
    if (_streamManualStop || _streamingVehicleId != vehicleId) return;

    _streamReconnectTimer?.cancel();
    final delay = _reconnectDelaysSeconds[_streamReconnectAttempts.clamp(0, _reconnectDelaysSeconds.length - 1)];
    _streamReconnectAttempts++;
    _streamReconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_streamManualStop && _streamingVehicleId == vehicleId) {
        _connectStreamingSocket(vehicleId);
      }
    });
  }

  void stopStreamingGPS() {
    _streamManualStop = true;
    _streamingVehicleId = null;
    _streamReconnectTimer?.cancel();
    _streamReconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastKnownPosition = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _streamingChannel?.sink.close();
    _streamingChannel = null;

    state = state.copyWith(isStreamingGPS: false);
  }
}

final gpsTrackingProvider = NotifierProvider<GpsTrackingNotifier, GpsTrackingState>(() => GpsTrackingNotifier());
