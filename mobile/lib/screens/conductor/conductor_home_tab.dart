import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/screens/tracker_screen.dart';

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
    final state = ref.read(appStateProvider);
    if (state.trips.isEmpty) {
      await state.loadTrips();
    }
    final trips = ref.read(appStateProvider).trips;
    if (trips.isNotEmpty) {
      final activeTrip = trips.first;
      final tripId = activeTrip['id'].toString();
      setState(() => _isLoadingManifest = true);
      final manifest = await state.fetchTripManifest(tripId);
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
    final state = ref.watch(appStateProvider);
    final conductorName =
        state.userName.isNotEmpty ? state.userName : 'Conductor';

    // Pick active assigned trip for conductor if available
    final activeTrip = state.trips.isNotEmpty ? state.trips.first : null;

    final String assignedBusText = activeTrip != null
        ? 'Assigned: ${activeTrip['reg'] ?? 'N/A'} (${activeTrip['bus_name'] ?? 'Bus'})'
        : 'Assigned: No Active Bus';

    final int totalSeats = activeTrip?['total_seats'] ?? 40;
    final List<dynamic> manifestList = _manifestData?['manifest'] ?? [];
    final List<dynamic> boardedList = _manifestData?['boarded_seats'] ?? (activeTrip?['boarded_seats'] ?? []);

    final int validatedCount = manifestList
        .where((m) => boardedList.contains(m['seat']))
        .length;
    final int bookedCount = manifestList.length;
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
                                    onChanged: (val) {
                                      setState(() => _isOnDuty = val);
                                      SeatyNotifications.show(
                                        context,
                                        val
                                            ? 'Status updated to ON DUTY'
                                            : 'Status updated to OFF DUTY',
                                      );
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
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                ),
              ),

              const SizedBox(height: 20),

              // ── CURRENT ASSIGNED TRIP ─────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
