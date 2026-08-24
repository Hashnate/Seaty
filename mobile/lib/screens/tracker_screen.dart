import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:seaty/main.dart';
import 'package:seaty/providers/active_trips_provider.dart';
import 'package:seaty/providers/gps_tracking_provider.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:flutter_animate/flutter_animate.dart';

// =====================================================================
// BOLD GRADIENT HERO HEADING — Reusable across screens
// =====================================================================
class BoldGradientHeroHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;

  const BoldGradientHeroHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailingIcon,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ShaderMask(
                shaderCallback: (bounds) =>
                    const LinearGradient(
                      colors: [
                        Color(0xFF0A2540), // Deep Navy
                        Color(0xFF1E40AF), // Royal Blue
                        Color(0xFF2563EB), // Vibrant Electric Blue
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(
                      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                    ),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.8,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            if (trailingIcon != null)
              GestureDetector(
                onTap: onTrailingTap,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    trailingIcon,
                    color: const Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: 44,
          height: 3.5,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
            ),
          ),
        ).animate().scaleX(duration: 400.ms, curve: Curves.easeOutCubic),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ],
    ).animate().fadeIn(duration: 350.ms).slideX(begin: -0.05, end: 0, duration: 350.ms, curve: Curves.easeOutCubic);
  }
}

// =====================================================================
// PROXIMITY STATUS MODELS & CITY COORDINATES
// =====================================================================
enum BusProximityStatus {
  approaching,
  arriving,
  passed,
  unknown,
}

class BusProximityInfo {
  final double distanceMeters;
  final String formattedDistance;
  final BusProximityStatus status;
  final String statusLabel;
  final Color statusColor;
  final IconData statusIcon;
  final String? etaText;

  const BusProximityInfo({
    required this.distanceMeters,
    required this.formattedDistance,
    required this.status,
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
    this.etaText,
  });
}

// =====================================================================
// LIVE TRACKER SCREEN — OpenStreetMap + Real-time User & Bus Location
// =====================================================================
class PassengerTrackingTab extends ConsumerStatefulWidget {
  final Map<String, dynamic>? trip;

  const PassengerTrackingTab({
    super.key,
    this.trip,
  });

  @override
  ConsumerState<PassengerTrackingTab> createState() =>
      _PassengerTrackingTabState();
}

class _PassengerTrackingTabState extends ConsumerState<PassengerTrackingTab> {
  String? _selectedBusId;
  Timer? _staleTicker;
  /// Guards the one-shot auto-start above from re-firing on every rebuild.
  bool _autoTrackStarted = false;
  Timer? _activeTripsRefreshTimer;

  // Passenger's Live Location State
  Position? _userPosition;
  bool _isLocationPermissionGranted = false;
  bool _isFetchingLocation = false;
  StreamSubscription<Position>? _userPositionStream;

  @override
  void initState() {
    super.initState();
    if (widget.trip != null) {
      _selectedBusId = widget.trip!['reg'] ?? widget.trip!['bus_reg'] ?? widget.trip!['bus_name'];
      // Arrived here from a ticket or notification - make sure the trackable
      // list is current so the pre-selected bus isn't silently deselected.
      Future.microtask(
        () => ref.read(activeTripsProvider.notifier).loadActiveTrips(),
      );
    }
    // Initialize passenger's own GPS location for distance & arrival calculation
    _initUserLocation();

    // Keeps the "last update Xs ago" / stale badge fresh without new GPS data arriving.
    _staleTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
    // A trip only becomes trackable 30 minutes before departure. Without this
    // the tab - built once and kept alive - would never notice that moment
    // arriving while the passenger sits waiting on it.
    _activeTripsRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) ref.read(activeTripsProvider.notifier).loadActiveTrips();
    });
  }

  @override
  void dispose() {
    _staleTicker?.cancel();
    _activeTripsRefreshTimer?.cancel();
    _userPositionStream?.cancel();
    super.dispose();
  }

  final MapController _mapController = MapController();
  bool _isDarkModeMap = false;
  String? _activeTooltip; // ID of marker currently showing popup ('bus', 'user', 'origin', 'destination', 'stop_X')

  // Sri Lanka center
  static final LatLng _sriLankaCenter = LatLng(7.8731, 80.7718);

  // Sri Lankan city coordinates for reliable arrival/pass computation
  static const Map<String, LatLng> _sriLankanCities = {
    'colombo': LatLng(6.9271, 79.8612),
    'kandy': LatLng(7.2906, 80.6337),
    'galle': LatLng(6.0535, 80.2210),
    'matara': LatLng(5.9549, 80.5550),
    'ella': LatLng(6.8667, 81.0466),
    'jaffna': LatLng(9.6615, 80.0255),
    'kurunegala': LatLng(7.4863, 80.3623),
    'negombo': LatLng(7.2008, 79.8737),
    'anuradhapura': LatLng(8.3114, 80.4037),
    'trincomalee': LatLng(8.5874, 81.2152),
    'batticaloa': LatLng(7.7102, 81.6924),
    'badulla': LatLng(6.9934, 81.0550),
    'nuwara eliya': LatLng(6.9497, 80.7891),
    'ratnapura': LatLng(6.6828, 80.4037),
    'hikkaduwa': LatLng(6.1405, 80.1001),
    'bentota': LatLng(6.4218, 79.9984),
    'kalutara': LatLng(6.5854, 79.9607),
    'panadura': LatLng(6.7132, 79.9074),
    'nittambuwa': LatLng(7.1444, 80.0956),
    'kegalle': LatLng(7.2513, 80.3464),
    'peradeniya': LatLng(7.2600, 80.5960),
    'dambulla': LatLng(7.8742, 80.6511),
    'sigiriya': LatLng(7.9570, 80.7603),
    'tangalle': LatLng(6.0244, 80.7941),
    'hambantota': LatLng(6.1248, 81.1185),
  };

  // Predefined route coordinates for common Sri Lankan bus routes
  static final Map<String, List<LatLng>> _routeCoordinates = {
    'Colombo-Kandy': [
      LatLng(6.9271, 79.8612), // Colombo
      LatLng(7.0480, 80.1130), // Nittambuwa
      LatLng(7.1840, 80.3550), // Kegalle
      LatLng(7.2520, 80.5090), // Peradeniya
      LatLng(7.2906, 80.6337), // Kandy
    ],
    'Colombo-Galle': [
      LatLng(6.9271, 79.8612), // Colombo
      LatLng(6.7360, 79.9090), // Kalutara
      LatLng(6.5850, 80.0270), // Bentota
      LatLng(6.4330, 80.0030), // Hikkaduwa
      LatLng(6.0535, 80.2210), // Galle
    ],
    'Colombo-Ella': [
      LatLng(6.9271, 79.8612), // Colombo
      LatLng(7.2906, 80.6337), // Kandy
      LatLng(7.1750, 80.7730), // Nuwara Eliya
      LatLng(6.9810, 80.7500), // Bandarawela
      LatLng(6.8667, 81.0466), // Ella
    ],
  };

  Future<void> _initUserLocation() async {
    if (_isFetchingLocation) return;
    setState(() => _isFetchingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLocationPermissionGranted = false;
          _isFetchingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          setState(() {
            _isLocationPermissionGranted = false;
            _isFetchingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        setState(() => _isLocationPermissionGranted = true);

        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        ).catchError((_) => Geolocator.getLastKnownPosition());

        if (mounted && pos != null) {
          setState(() {
            _userPosition = pos;
            _isFetchingLocation = false;
          });
        }

        // Live passenger location stream with 5m filter
        _userPositionStream?.cancel();
        _userPositionStream = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((newPos) {
          if (mounted) {
            setState(() => _userPosition = newPos);
          }
        });
      }
    } catch (e) {
      debugPrint('Error initializing user location: $e');
      if (mounted) {
        setState(() => _isFetchingLocation = false);
      }
    }
  }

  BusProximityInfo? _calculateProximityInfo({
    required LatLng busPos,
    required LatLng userPos,
    required double busSpeedKmh,
    required String? destinationCity,
    required List<LatLng> routePoints,
  }) {
    final distanceMeters = Geolocator.distanceBetween(
      userPos.latitude,
      userPos.longitude,
      busPos.latitude,
      busPos.longitude,
    );

    final formattedDist = distanceMeters < 1000
        ? '${distanceMeters.round()} m'
        : '${(distanceMeters / 1000).toStringAsFixed(1)} km';

    // ETA calculation based on current bus speed (fallback to 28 km/h city avg if stationary)
    final effectiveSpeed = busSpeedKmh > 6.0 ? busSpeedKmh : 28.0;
    final etaMinutes = ((distanceMeters / 1000) / effectiveSpeed * 60).round();
    final etaText = etaMinutes <= 1 ? '< 1 min' : '~$etaMinutes mins';

    // Determine destination coordinates to know the directional flow
    LatLng? destCoord;
    if (routePoints.isNotEmpty) {
      destCoord = routePoints.last;
    } else if (destinationCity != null && destinationCity.isNotEmpty) {
      final key = destinationCity.toLowerCase().trim();
      destCoord = _sriLankanCities[key];
    }

    BusProximityStatus status = BusProximityStatus.approaching;
    String statusLabel = 'Approaching You • $formattedDist';
    Color statusColor = const Color(0xFF10B981); // Emerald
    IconData statusIcon = Icons.directions_bus_rounded;

    if (distanceMeters <= 200) {
      status = BusProximityStatus.arriving;
      statusLabel = 'Arriving Now • Within 200m';
      statusColor = const Color(0xFF059669);
      statusIcon = Icons.near_me_rounded;
    } else if (destCoord != null) {
      final busToDest = Geolocator.distanceBetween(
        busPos.latitude,
        busPos.longitude,
        destCoord.latitude,
        destCoord.longitude,
      );
      final userToDest = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        destCoord.latitude,
        destCoord.longitude,
      );

      // If bus is closer to the destination than the user by > 250m, it has passed the user's stop
      if (busToDest < userToDest - 250) {
        status = BusProximityStatus.passed;
        statusLabel = 'Bus Passed You • $formattedDist ahead';
        statusColor = const Color(0xFFE11D48); // Rose/Red
        statusIcon = Icons.history_rounded;
      } else {
        status = BusProximityStatus.approaching;
        statusLabel = 'Approaching You • $formattedDist ($etaText)';
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.directions_bus_rounded;
      }
    } else {
      status = BusProximityStatus.approaching;
      statusLabel = 'Approaching You • $formattedDist ($etaText)';
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.directions_bus_rounded;
    }

    return BusProximityInfo(
      distanceMeters: distanceMeters,
      formattedDistance: formattedDist,
      status: status,
      statusLabel: statusLabel,
      statusColor: statusColor,
      statusIcon: statusIcon,
      etaText: etaText,
    );
  }

  List<LatLng> _getRouteForTrip(List<Map<String, dynamic>> trips, String? selectedBusId) {
    if (selectedBusId == null) return [];

    final trip = trips.firstWhere(
      (t) => t['reg'] == selectedBusId,
      orElse: () => <String, dynamic>{},
    );

    if (trip.isEmpty) return [];

    final origin = trip['origin']?.toString() ?? '';
    final destination = trip['destination']?.toString() ?? '';
    final routeKey = '$origin-$destination';

    return _routeCoordinates[routeKey] ?? [];
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, (currentZoom + 1).clamp(3.0, 19.0));
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, (currentZoom - 1).clamp(3.0, 19.0));
  }

  void _fitRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    _mapController.move(LatLng(centerLat, centerLng), 9.0);
  }

  void _fitBusAndUser(LatLng bus, LatLng user) {
    final minLat = math.min(bus.latitude, user.latitude);
    final maxLat = math.max(bus.latitude, user.latitude);
    final minLng = math.min(bus.longitude, user.longitude);
    final maxLng = math.max(bus.longitude, user.longitude);
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    final dist = Geolocator.distanceBetween(bus.latitude, bus.longitude, user.latitude, user.longitude);
    double zoom = 14.0;
    if (dist > 80000) {
      zoom = 8.5;
    } else if (dist > 40000) {
      zoom = 9.8;
    } else if (dist > 15000) {
      zoom = 11.2;
    } else if (dist > 5000) {
      zoom = 12.5;
    } else if (dist > 2000) {
      zoom = 13.8;
    } else {
      zoom = 14.8;
    }

    _mapController.move(center, zoom);
  }

  @override
  Widget build(BuildContext context) {
    final gpsState = ref.watch(gpsTrackingProvider);

    // Sourced from `GET /trips/my-active`, not the home-search list.
    final activeTripsState = ref.watch(activeTripsProvider);
    final trackableTrips = activeTripsState.trips;

    final Map<String, Map<String, dynamic>> trackableByReg = {};
    for (final t in trackableTrips) {
      final reg = t['reg']?.toString();
      if (reg != null && reg.isNotEmpty) {
        trackableByReg.putIfAbsent(reg, () => t);
      }
    }
    final dedupedTrackableTrips = trackableByReg.values.toList();

    final hasSelected = trackableTrips.any((t) => t['reg'] == _selectedBusId);
    final String? selectedValue = hasSelected ? _selectedBusId : null;

    final Map<String, dynamic> currentTrip = dedupedTrackableTrips.firstWhere(
      (t) => t['reg'] == _selectedBusId,
      orElse: () => <String, dynamic>{},
    );

    if (_selectedBusId != null && !hasSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(gpsTrackingProvider.notifier).stopTracking();
        setState(() {
          _selectedBusId = null;
        });
      });
    }

    // Opened from a ticket or notification: auto-start socket
    if (hasSelected && !gpsState.isTracking && !_autoTrackStarted) {
      final vehicleId = currentTrip['vehicle_id']?.toString() ?? '';
      if (vehicleId.isNotEmpty) {
        _autoTrackStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(gpsTrackingProvider.notifier).startTracking(vehicleId);
          }
        });
      }
    }

    final isTracking = gpsState.isTracking && gpsState.trackedBusLocation != null && hasSelected;

    final secondsSinceUpdate = gpsState.lastUpdateAt == null
        ? null
        : DateTime.now().difference(gpsState.lastUpdateAt!).inSeconds;
    final isStaleUpdate = secondsSinceUpdate != null && secondsSinceUpdate > 30;

    LatLng? busPosition;
    double busSpeed = 0.0;
    if (isTracking) {
      final lat = (gpsState.trackedBusLocation!['latitude'] as num?)?.toDouble();
      final lng = (gpsState.trackedBusLocation!['longitude'] as num?)?.toDouble();
      busSpeed = (gpsState.trackedBusLocation!['speed'] as num?)?.toDouble() ?? 0.0;
      if (lat != null && lng != null) {
        busPosition = LatLng(lat, lng);
      }
    }

    LatLng? userLatLng = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : null;

    final routePoints = _getRouteForTrip(dedupedTrackableTrips, selectedValue);

    // Compute real-time proximity info (distance, approaching vs passed status, ETA)
    BusProximityInfo? proximityInfo;
    if (busPosition != null && userLatLng != null) {
      proximityInfo = _calculateProximityInfo(
        busPos: busPosition,
        userPos: userLatLng,
        busSpeedKmh: busSpeed,
        destinationCity: currentTrip['destination']?.toString(),
        routePoints: routePoints,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bold Gradient Hero Heading ──
            const Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 16),
              child: BoldGradientHeroHeading(
                title: 'Live Tracker',
                subtitle: 'Track buses and your live proximity on the map.',
              ),
            ),
            const SizedBox(height: 14),

            // ── Bus Selector Card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0A2540).withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.directions_bus_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        isDense: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          hintText: 'Select bus to track',
                          hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                        style: const TextStyle(
                          color: Color(0xFF0A2540),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        value: selectedValue,
                        items: dedupedTrackableTrips.map((trip) {
                          return DropdownMenuItem<String>(
                            value: trip['reg'],
                            child: Text(
                              '${trip['bus_name']} (${trip['reg']})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedBusId = val;
                            _activeTooltip = 'bus';
                          });
                          if (val != null) {
                            final selected = dedupedTrackableTrips.firstWhere(
                              (t) => t['reg'] == val,
                              orElse: () => <String, dynamic>{},
                            );
                            final vehicleId =
                                selected['vehicle_id']?.toString() ?? '';
                            if (vehicleId.isNotEmpty) {
                              ref
                                  .read(gpsTrackingProvider.notifier)
                                  .startTracking(vehicleId);
                            }
                          } else {
                            ref.read(gpsTrackingProvider.notifier).stopTracking();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Interactive OpenStreetMap Container ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: 12,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0A2540).withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Flutter Map (Interactive)
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: busPosition ?? userLatLng ?? _sriLankaCenter,
                          initialZoom: isTracking ? 14.0 : 7.6,
                          minZoom: 6.0,
                          maxZoom: 18.0,
                          onTap: (tapPosition, point) {
                            setState(() => _activeTooltip = null);
                          },
                        ),
                        children: [
                          // Dynamic Tile Layer (Light vs Dark toggleable)
                          TileLayer(
                            urlTemplate: _isDarkModeMap
                                ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                                : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'lk.seaty.app',
                            maxZoom: 19,
                            keepBuffer: 4,
                          ),

                          // Route Polyline Layer
                          if (routePoints.isNotEmpty)
                            PolylineLayer(
                              polylines: <Polyline<Object>>[
                                Polyline(
                                  points: routePoints,
                                  color: const Color(0xFF2563EB),
                                  strokeWidth: 4.5,
                                ),
                              ],
                            ),

                          // Dotted Live Guide Line between Passenger and Bus
                          if (busPosition != null && userLatLng != null)
                            PolylineLayer(
                              polylines: <Polyline<Object>>[
                                Polyline(
                                  points: [userLatLng, busPosition],
                                  color: proximityInfo?.statusColor.withValues(alpha: 0.6) ?? const Color(0xFF0284C7).withValues(alpha: 0.6),
                                  strokeWidth: 2.5,
                                  pattern: const StrokePattern.dotted(
                                    spacingFactor: 2.0,
                                  ),
                                ),
                              ],
                            ),

                          // Route Endpoint & Intermediate Markers
                          if (routePoints.length >= 2)
                            MarkerLayer(
                              markers: [
                                // ── Origin Marker ──
                                Marker(
                                  point: routePoints.first,
                                  width: 32,
                                  height: 32,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _activeTooltip = _activeTooltip == 'origin' ? null : 'origin';
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),

                                // ── Intermediate Stop Markers ──
                                ...List.generate(
                                  routePoints.length > 2 ? routePoints.length - 2 : 0,
                                  (idx) {
                                    final stopIndex = idx + 1;
                                    final stopPoint = routePoints[stopIndex];
                                    final stopId = 'stop_$stopIndex';
                                    return Marker(
                                      point: stopPoint,
                                      width: 18,
                                      height: 18,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _activeTooltip = _activeTooltip == stopId ? null : stopId;
                                          });
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: const Color(0xFF2563EB),
                                              width: 3,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.15),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                                // ── Destination Marker ──
                                Marker(
                                  point: routePoints.last,
                                  width: 32,
                                  height: 32,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _activeTooltip = _activeTooltip == 'destination' ? null : 'destination';
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC62828),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFC62828).withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.flag_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                          // ── Live Passenger Location Marker ──
                          if (userLatLng != null)
                            MarkerLayer(
                              markers: [
                                // Radar pulse ring
                                Marker(
                                  point: userLatLng,
                                  width: 58,
                                  height: 58,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF0284C7).withValues(alpha: 0.16),
                                      border: Border.all(
                                        color: const Color(0xFF0284C7).withValues(alpha: 0.4),
                                        width: 1.5,
                                      ),
                                    ),
                                  ).animate(onPlay: (c) => c.repeat())
                                   .scale(begin: const Offset(0.75, 0.75), end: const Offset(1.2, 1.2), duration: 1400.ms, curve: Curves.easeOut),
                                ),
                                // Inner user avatar dot
                                Marker(
                                  point: userLatLng,
                                  width: 36,
                                  height: 36,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _activeTooltip = _activeTooltip == 'user' ? null : 'user';
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF0284C7).withValues(alpha: 0.5),
                                            blurRadius: 10,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.person_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                          // ── Live Bus Marker + Pulse Effect ──
                          if (busPosition != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: busPosition,
                                  width: 64,
                                  height: 64,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                                      border: Border.all(
                                        color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                                        width: 2,
                                      ),
                                    ),
                                  ).animate(onPlay: (controller) => controller.repeat())
                                   .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.15, 1.15), duration: 1200.ms, curve: Curves.easeInOut),
                                ),
                                Marker(
                                  point: busPosition,
                                  width: 44,
                                  height: 44,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _activeTooltip = _activeTooltip == 'bus' ? null : 'bus';
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF2563EB), Color(0xFF00C853)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 3,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF2563EB).withValues(alpha: 0.5),
                                            blurRadius: 14,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.directions_bus_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),

                      // ── Interactive Callout Popup Bubble ──
                      if (_activeTooltip != null)
                        Positioned(
                          top: 56,
                          left: 20,
                          right: 20,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A2540),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _activeTooltip == 'bus'
                                      ? Icons.directions_bus_filled_rounded
                                      : _activeTooltip == 'user'
                                          ? Icons.person_pin_circle_rounded
                                          : _activeTooltip == 'origin'
                                              ? Icons.play_circle_fill_rounded
                                              : _activeTooltip == 'destination'
                                                  ? Icons.flag_circle_rounded
                                                  : Icons.location_on_rounded,
                                  color: const Color(0xFF60A5FA),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _activeTooltip == 'bus'
                                            ? 'Bus ${_selectedBusId ?? "Active"}'
                                            : _activeTooltip == 'user'
                                                ? 'Your Current Location'
                                                : _activeTooltip == 'origin'
                                                    ? 'Trip Origin'
                                                    : _activeTooltip == 'destination'
                                                        ? 'Final Destination'
                                                        : 'Intermediate Stop',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _activeTooltip == 'bus'
                                            ? (gpsState.trackedBusLocation != null
                                                ? 'Live speed: ${gpsState.trackedBusLocation!['speed']?.toStringAsFixed(0) ?? "0"} km/h${proximityInfo != null ? " • ${proximityInfo.formattedDistance} from you" : ""}'
                                                : 'Waiting for driver to start broadcasting…')
                                            : _activeTooltip == 'user'
                                                ? (proximityInfo != null
                                                    ? '${proximityInfo.statusLabel} • Lat ${_userPosition?.latitude.toStringAsFixed(4)}, Lng ${_userPosition?.longitude.toStringAsFixed(4)}'
                                                    : 'GPS Fix Active • Accuracy within 10m')
                                                : _activeTooltip == 'origin'
                                                    ? 'Journey Start Point'
                                                    : _activeTooltip == 'destination'
                                                        ? 'Final Dropoff Station'
                                                        : 'Passenger boarding & dropoff station',
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() => _activeTooltip = null),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2, end: 0, duration: 200.ms),
                        ),

                      // ── Live Status & Proximity Badge (Top Left) ──
                      Positioned(
                        top: 12,
                        left: 12,
                        child: proximityInfo != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: proximityInfo.statusColor.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      proximityInfo.statusIcon,
                                      color: Colors.white,
                                      size: 13,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      proximityInfo.statusLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(duration: 250.ms)
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isTracking
                                      ? const Color(0xFF10B981).withValues(alpha: 0.95)
                                      : const Color(0xFF0A2540).withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: isTracking ? Colors.white : const Color(0xFF64748B),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isTracking ? 'LIVE TRACKING' : 'IDLE',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),

                      // ── Floating Interactive Map Control Bar — Top Right ──
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Recenter on Bus
                              if (isTracking && busPosition != null) ...[
                                _buildMapControlButton(
                                  icon: Icons.directions_bus_rounded,
                                  tooltip: 'Center on Bus',
                                  color: const Color(0xFF2563EB),
                                  onTap: () {
                                    _mapController.move(busPosition!, 14.5);
                                  },
                                ),
                                const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                              ],
                              // Fit Both Bus & User
                              if (isTracking && busPosition != null && userLatLng != null) ...[
                                _buildMapControlButton(
                                  icon: Icons.swap_calls_rounded,
                                  tooltip: 'Fit Bus & My Location',
                                  color: const Color(0xFF0284C7),
                                  onTap: () {
                                    _fitBusAndUser(busPosition!, userLatLng);
                                  },
                                ),
                                const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                              ],
                              // Recenter on Passenger Location
                              if (userLatLng != null) ...[
                                _buildMapControlButton(
                                  icon: Icons.my_location_rounded,
                                  tooltip: 'Center on Me',
                                  color: const Color(0xFF0284C7),
                                  onTap: () {
                                    _mapController.move(userLatLng, 15.0);
                                  },
                                ),
                                const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                              ] else ...[
                                _buildMapControlButton(
                                  icon: Icons.location_searching_rounded,
                                  tooltip: 'Enable My Location',
                                  color: const Color(0xFF64748B),
                                  onTap: _initUserLocation,
                                ),
                                const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                              ],
                              // Fit Route
                              if (routePoints.isNotEmpty) ...[
                                _buildMapControlButton(
                                  icon: Icons.center_focus_strong_rounded,
                                  tooltip: 'Fit Route',
                                  color: const Color(0xFF0A2540),
                                  onTap: () => _fitRoute(routePoints),
                                ),
                                const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                              ],
                              // Zoom In
                              _buildMapControlButton(
                                icon: Icons.add_rounded,
                                tooltip: 'Zoom In',
                                color: const Color(0xFF334155),
                                onTap: _zoomIn,
                              ),
                              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                              // Zoom Out
                              _buildMapControlButton(
                                icon: Icons.remove_rounded,
                                tooltip: 'Zoom Out',
                                color: const Color(0xFF334155),
                                onTap: _zoomOut,
                              ),
                              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                              // Map Theme Toggle
                              _buildMapControlButton(
                                icon: _isDarkModeMap ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                tooltip: _isDarkModeMap ? 'Light Map' : 'Dark Map',
                                color: _isDarkModeMap ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
                                onTap: () {
                                  setState(() => _isDarkModeMap = !_isDarkModeMap);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Floating Bottom Info Card + Quick Actions ──
                      if (isTracking && busPosition != null)
                        Positioned(
                          bottom: 14,
                          left: 14,
                          right: 14,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.directions_bus_filled_rounded,
                                        color: Color(0xFF2563EB),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${currentTrip['bus_name'] ?? "Bus"} (${_selectedBusId ?? "Active"})',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                              color: Color(0xFF0A2540),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            currentTrip['origin'] != null && currentTrip['destination'] != null
                                                ? '${currentTrip['origin']} → ${currentTrip['destination']}'
                                                : '${gpsState.trackedBusLocation!['latitude']?.toStringAsFixed(4)}, ${gpsState.trackedBusLocation!['longitude']?.toStringAsFixed(4)}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Contact Conductor Quick Action Button
                                    GestureDetector(
                                      onTap: () async {
                                        final phone = currentTrip['conductor_phone']
                                                ?.toString()
                                                .trim() ??
                                            '';
                                        if (phone.isEmpty) {
                                          SeatyNotifications.show(
                                            context,
                                            'No contact number available for this bus\'s conductor.',
                                            isWarning: true,
                                          );
                                          return;
                                        }
                                        final uri = Uri.parse('tel:$phone');
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri);
                                        } else if (context.mounted) {
                                          SeatyNotifications.show(
                                            context,
                                            'Could not open the dialer for $phone',
                                            isError: true,
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.phone_rounded, color: Color(0xFF2563EB), size: 14),
                                            SizedBox(width: 4),
                                            Text(
                                              'Call',
                                              style: TextStyle(
                                                color: Color(0xFF2563EB),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    if (proximityInfo != null) ...[
                                      _buildStatChip(
                                        Icons.place_rounded,
                                        proximityInfo.formattedDistance,
                                        'to you',
                                        const Color(0xFF0284C7),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatChip(
                                        Icons.speed_rounded,
                                        '${busSpeed.toStringAsFixed(0)}',
                                        'km/h',
                                        const Color(0xFF2563EB),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatChip(
                                        proximityInfo.status == BusProximityStatus.passed
                                            ? Icons.history_rounded
                                            : Icons.timer_outlined,
                                        proximityInfo.status == BusProximityStatus.passed
                                            ? 'Passed'
                                            : (proximityInfo.etaText ?? 'Live'),
                                        proximityInfo.status == BusProximityStatus.passed
                                            ? 'status'
                                            : 'arrival',
                                        proximityInfo.statusColor,
                                      ),
                                    ] else ...[
                                      _buildStatChip(
                                        Icons.speed_rounded,
                                        '${busSpeed.toStringAsFixed(0)}',
                                        'km/h',
                                        const Color(0xFF2563EB),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatChip(
                                        Icons.explore_rounded,
                                        '${gpsState.trackedBusLocation!['heading']?.toStringAsFixed(0) ?? '0'}°',
                                        'bearing',
                                        const Color(0xFF0A2540),
                                      ),
                                      const SizedBox(width: 8),
                                      if (gpsState.isReconnecting)
                                        _buildStatChip(
                                          Icons.sync_rounded,
                                          'Reconnecting',
                                          'connection',
                                          const Color(0xFFF59E0B),
                                        )
                                      else if (isStaleUpdate)
                                        _buildStatChip(
                                          Icons.warning_amber_rounded,
                                          '${secondsSinceUpdate}s ago',
                                          'stale',
                                          const Color(0xFFF59E0B),
                                        )
                                      else
                                        _buildStatChip(
                                          Icons.signal_cellular_alt_rounded,
                                          'Live',
                                          'connection',
                                          const Color(0xFF10B981),
                                        ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (_selectedBusId == null)
                        Positioned(
                          bottom: 14,
                          left: 14,
                          right: 14,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFF94A3B8),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Select a bus from the dropdown above to start live tracking.',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (_userPosition == null) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _initUserLocation,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.my_location_rounded, size: 14, color: Color(0xFF0284C7)),
                                          SizedBox(width: 4),
                                          Text(
                                            'My GPS',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0284C7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
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
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: color.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
