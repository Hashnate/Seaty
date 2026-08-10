import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:seaty/main.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/screens/tracker_screen.dart';
import 'package:seaty/utils/active_trip.dart';
import 'package:seaty/widgets/seaty_bus_loading.dart';
import 'package:seaty/widgets/shimmer_loading.dart';

class ConductorHomeTab extends ConsumerStatefulWidget {
  final Function(int tabIndex)? onNavigate;
  const ConductorHomeTab({super.key, this.onNavigate});

  @override
  ConsumerState<ConductorHomeTab> createState() => _ConductorHomeTabState();
}

class _ConductorHomeTabState extends ConsumerState<ConductorHomeTab> {
  bool _isOnDuty = true;
  Map<String, dynamic>? _manifestData;
  bool _isLoadingManifest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadActiveManifest();
    });
  }

  Future<void> _loadActiveManifest() async {
    final tripsNotifier = ref.read(tripsProvider.notifier);
    final bookingsNotifier = ref.read(bookingsProvider.notifier);

    // Always refetch. Guarding on `isEmpty` meant a list left behind by a
    // previously signed-in conductor was treated as good enough, so the screen
    // showed the wrong company's bus and manifest after an account switch.
    await tripsNotifier.loadTrips();
    final trips = ref.read(tripsProvider).trips;
    final activeTrip = pickActiveTrip(trips);
    if (activeTrip != null) {
      final tripId = activeTrip['id'].toString();
      setState(() => _isLoadingManifest = true);
      final manifest = await bookingsNotifier.fetchTripManifest(tripId);
      if (mounted) {
        setState(() {
          _manifestData = manifest;
          _isLoadingManifest = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tripsState = ref.watch(tripsProvider);
    final conductorName =
        authState.userName.isNotEmpty ? authState.userName : 'Conductor';

    // Pick active assigned trip for conductor if available - the journey under
    // way wins over the day's next departure (matters for overnight runs).
    final activeTrip = pickActiveTrip(tripsState.trips);

    // Until the first fetch resolves there is nothing to show - and the empty
    // state ("No Active Bus", 40 seats, LKR 0) is indistinguishable from real
    // data, so it reads as fabricated. Show skeletons instead, and only claim
    // "no trip" once the request has actually come back.
    final bool isInitialLoad = tripsState.isLoading && tripsState.trips.isEmpty;

    final String assignedBusText = activeTrip != null
        ? 'Assigned: ${activeTrip['reg'] ?? 'N/A'} (${activeTrip['bus_name'] ?? 'Bus'})'
        : 'Assigned: No Active Bus';

    final int totalSeats = activeTrip?['total_seats'] ?? 40;
    final List<dynamic> bookedSeats = activeTrip?['booked_seats'] ?? [];
    final List<dynamic> manifestList = _manifestData?['manifest'] ?? [];
    final List<dynamic> boardedList = _manifestData?['boarded_seats'] ?? (activeTrip?['boarded_seats'] ?? []);

    final int validatedCount = boardedList.length;
    final int bookedCount = bookedSeats.isNotEmpty ? bookedSeats.length : manifestList.length;
    final int availableSeats = (totalSeats - bookedCount) > 0 ? (totalSeats - bookedCount) : 0;
    final double pricePerSeat = activeTrip?['price'] ?? 0.0;
    final double totalCash = bookedCount * pricePerSeat;

    final String origin = activeTrip?['origin'] ?? 'No Scheduled Origin';
    final String destination = activeTrip?['destination'] ?? 'No Scheduled Destination';
    final String departure = activeTrip?['departure'] ?? 'N/A';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HERO HEADER ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 12),
                child: BoldGradientHeroHeading(
                  title: 'On-Board Central',
                  subtitle: 'Manage duty, ticket verification & passengers.',
                ),
              ),
              const SizedBox(height: 12),

              // ── ACTIVE BUS BANNER & ON-DUTY TOGGLE ──────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        // Background Texture Image
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/revenue_banner_bg.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        // Dark Gradient Overlay
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF0F172A).withValues(alpha: 0.88),
                                  const Color(0xFF1E293B).withValues(alpha: 0.94),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                        // Banner Body Content
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: const Color(
                                          0xFF2563EB,
                                        ).withValues(alpha: 0.2),
                                        child: const Icon(
                                          Icons.badge_rounded,
                                          color: Color(0xFF2563EB),
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            conductorName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          if (isInitialLoad)
                                            SeatyShimmer(
                                              child: Container(
                                                height: 12,
                                                width: 160,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                              ),
                                            )
                                          else
                                            Text(
                                              assignedBusText,
                                              style: const TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(
                                color: Color(0xFF334155),
                                height: 1,
                              ),
                              const SizedBox(height: 14),

                              // Duty Status Toggle Row
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _isOnDuty
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFEF4444),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isOnDuty
                                            ? 'ON DUTY • ACTIVE'
                                            : 'OFF DUTY',
                                        style: TextStyle(
                                          color: _isOnDuty
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFEF4444),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Switch(
                                    value: _isOnDuty,
                                    activeThumbColor: const Color(0xFF2563EB),
                                    activeTrackColor: const Color(
                                      0xFF2563EB,
                                    ).withValues(alpha: 0.3),
                                    onChanged: (val) async {
                                      setState(() => _isOnDuty = val);
                                      if (val) {
                                        SeatyNotifications.show(
                                          context,
                                          'Status updated to ON DUTY',
                                        );
                                        if (activeTrip != null) {
                                          final vehicleId = activeTrip['vehicle_id']?.toString() ?? '';
                                          if (vehicleId.isNotEmpty) {
                                            bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                                            LocationPermission permission = await Geolocator.checkPermission();
                                            if (serviceEnabled && permission != LocationPermission.denied) {
                                              await ref.read(gpsTrackingProvider.notifier).startStreamingGPS(vehicleId, true);
                                            } else {
                                              if (mounted) {
                                                SeatyNotifications.show(
                                                  context,
                                                  'Please enable GPS to start location broadcast.',
                                                  isWarning: true,
                                                );
                                              }
                                            }
                                          }
                                        }
                                      } else {
                                        ref.read(gpsTrackingProvider.notifier).stopStreamingGPS();
                                        SeatyNotifications.show(
                                          context,
                                          'Status updated to OFF DUTY',
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── TODAY'S OVERVIEW STATS ──────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Today\'s Boarding Overview',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (_isLoadingManifest)
                          const SeatyBusLoadingIndicator.small(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isInitialLoad) ...[
                      const Row(
                        children: [
                          Expanded(child: StatTileSkeleton()),
                          SizedBox(width: 12),
                          Expanded(child: StatTileSkeleton()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const StatTileSkeleton(),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatTile(
                              title: 'Validated',
                              value: '$validatedCount / $bookedCount',
                              subtitle: 'Passengers',
                              icon: Icons.check_circle_rounded,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatTile(
                              title: 'Available',
                              value: '$availableSeats Seats',
                              subtitle: 'Remaining',
                              icon: Icons.event_seat_rounded,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildStatTile(
                        title: 'Cash Collected',
                        value: 'LKR ${totalCash.toStringAsFixed(0)}',
                        subtitle: 'From $bookedCount verified tickets today',
                        icon: Icons.payments_rounded,
                        color: const Color(0xFF2563EB),
                        isFullWidth: true,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── CURRENT ASSIGNED TRIP ─────────────────────
              if (isInitialLoad)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: SeatyShimmer(
                    child: SizedBox(
                      height: 132,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                        child: SizedBox(width: double.infinity),
                      ),
                    ),
                  ),
                )
              else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: activeTrip == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            SeatyPageRoute(
                              page: ConductorTripDetailsScreen(trip: activeTrip),
                            ),
                          );
                        },
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Active Schedule',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF10B981,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                activeTrip != null ? 'EN ROUTE' : 'NO TRIP',
                                style: TextStyle(
                                  color: activeTrip != null
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '$origin → $destination',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Departure: $departure',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool isFullWidth = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
