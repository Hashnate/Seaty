import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:seaty/main.dart';

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
                        Color(0xFF0A2540), // Seaty Theme Blue
                        Color(0xFF001220), // Dark Midnight Blue
                        Color(0xFF000814), // Darkest Navy
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
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
            ),
          ),
        ),
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
    );
  }
}

// =====================================================================
// LIVE TRACKER SCREEN — OpenStreetMap (Free, No API Key)
// =====================================================================
class PassengerTrackingTab extends ConsumerStatefulWidget {
  const PassengerTrackingTab({super.key});

  @override
  ConsumerState<PassengerTrackingTab> createState() =>
      _PassengerTrackingTabState();
}

class _PassengerTrackingTabState extends ConsumerState<PassengerTrackingTab> {
  String? _selectedBusId;
  final MapController _mapController = MapController();

  // Sri Lanka center
  static final LatLng _sriLankaCenter = LatLng(7.8731, 80.7718);

  // Predefined route coordinates for common Sri Lankan bus routes
  static final Map<String, List<LatLng>> _routeCoordinates = {
    'Colombo-Kandy': [
      LatLng(6.9271, 79.8612),
      LatLng(7.0480, 80.1130),
      LatLng(7.1840, 80.3550),
      LatLng(7.2520, 80.5090),
      LatLng(7.2906, 80.6337),
    ],
    'Colombo-Galle': [
      LatLng(6.9271, 79.8612),
      LatLng(6.7360, 79.9090),
      LatLng(6.5850, 80.0270),
      LatLng(6.4330, 80.0030),
      LatLng(6.0535, 80.2210),
    ],
    'Colombo-Ella': [
      LatLng(6.9271, 79.8612),
      LatLng(7.2906, 80.6337),
      LatLng(7.1750, 80.7730),
      LatLng(6.9810, 80.7500),
      LatLng(6.8667, 81.0466),
    ],
  };

  List<LatLng> _getRouteForTrip(AppState state) {
    if (_selectedBusId == null) return [];

    final trip = state.trips.firstWhere(
      (t) => t['reg'] == _selectedBusId,
      orElse: () => <String, dynamic>{},
    );

    if (trip.isEmpty) return [];

    final origin = trip['origin']?.toString() ?? '';
    final destination = trip['destination']?.toString() ?? '';
    final routeKey = '$origin-$destination';

    return _routeCoordinates[routeKey] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isTracking = state.isTracking && state.trackedBusLocation != null;

    LatLng? busPosition;
    if (isTracking) {
      final lat = state.trackedBusLocation!['latitude'] as double?;
      final lng = state.trackedBusLocation!['longitude'] as double?;
      if (lat != null && lng != null) {
        busPosition = LatLng(lat, lng);
      }
    }

    final routePoints = _getRouteForTrip(state);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bold Gradient Hero Heading ──
            const Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 20),
              child: BoldGradientHeroHeading(
                title: 'Live Tracker',
                subtitle: 'Track buses in real-time on the map.',
              ),
            ),
            const SizedBox(height: 16),

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
                        value: _selectedBusId,
                        items: state.trips.map((trip) {
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
                          setState(() => _selectedBusId = val);
                          if (val != null) {
                            state.startTracking(val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── OpenStreetMap ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: 110,
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
                      // Flutter Map (OpenStreetMap)
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: busPosition ?? _sriLankaCenter,
                          initialZoom: isTracking ? 14.0 : 8.0,
                        ),
                        children: [
                          // Dark-themed tile layer (CartoDB Dark Matter — free)
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'lk.seaty.app',
                            maxZoom: 19,
                          ),

                          // Route polyline
                          if (routePoints.isNotEmpty)
                            PolylineLayer(
                              polylines: <Polyline<Object>>[
                                Polyline(
                                  points: routePoints,
                                  color: const Color(0xFF2563EB),
                                  strokeWidth: 4.0,
                                ),
                              ],
                            ),

                          // Route endpoint markers (origin + destination)
                          if (routePoints.length >= 2)
                            MarkerLayer(
                              markers: [
                                // Origin marker
                                Marker(
                                  point: routePoints.first,
                                  width: 28,
                                  height: 28,
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
                                          color: const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                                // Destination marker
                                Marker(
                                  point: routePoints.last,
                                  width: 28,
                                  height: 28,
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
                                          color: const Color(
                                            0xFFC62828,
                                          ).withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.flag_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                          // Live bus marker
                          if (busPosition != null)
                            MarkerLayer(
                              markers: [
                                // Outer glow ring
                                Marker(
                                  point: busPosition,
                                  width: 60,
                                  height: 60,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(
                                        0xFF2563EB,
                                      ).withValues(alpha: 0.12),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF2563EB,
                                        ).withValues(alpha: 0.25),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                // Bus icon marker
                                Marker(
                                  point: busPosition,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF2563EB),
                                          Color(0xFFFF6D00),
                                        ],
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
                                          color: const Color(
                                            0xFF2563EB,
                                          ).withValues(alpha: 0.5),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.directions_bus_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),

                      // Status badge — top left
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isTracking
                                ? const Color(0xFF10B981).withValues(alpha: 0.9)
                                : const Color(
                                    0xFF0A2540,
                                  ).withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
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
                                  color: isTracking
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isTracking ? 'LIVE' : 'IDLE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Re-center button — top right
                      if (isTracking && busPosition != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: GestureDetector(
                            onTap: () {
                              _mapController.move(busPosition!, 14.0);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.my_location_rounded,
                                size: 18,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ),

                      // ── Floating Bottom Info Card ──
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
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF2563EB,
                                        ).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.directions_bus_filled_rounded,
                                        color: Color(0xFF2563EB),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _selectedBusId ?? 'Bus',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                              color: Color(0xFF0A2540),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${state.trackedBusLocation!['latitude']?.toStringAsFixed(4)}, ${state.trackedBusLocation!['longitude']?.toStringAsFixed(4)}',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              color: Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _buildStatChip(
                                      Icons.speed_rounded,
                                      '${state.trackedBusLocation!['speed']?.toStringAsFixed(0) ?? '0'}',
                                      'km/h',
                                      const Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildStatChip(
                                      Icons.explore_rounded,
                                      '${state.trackedBusLocation!['heading']?.toStringAsFixed(0) ?? '0'}°',
                                      'bearing',
                                      const Color(0xFF0A2540),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildStatChip(
                                      Icons.signal_cellular_alt_rounded,
                                      'Strong',
                                      'signal',
                                      const Color(0xFF10B981),
                                    ),
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
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFF94A3B8),
                                  size: 20,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Select a bus from the dropdown above to start live tracking.',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
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
              ),
            ),
          ],
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
