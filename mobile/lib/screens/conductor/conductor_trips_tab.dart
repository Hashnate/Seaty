import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/screens/tracker_screen.dart';
import 'package:seaty/widgets/shimmer_loading.dart';

class ConductorTripsTab extends ConsumerStatefulWidget {
  const ConductorTripsTab({super.key});

  @override
  ConsumerState<ConductorTripsTab> createState() => _ConductorTripsTabState();
}

class _ConductorTripsTabState extends ConsumerState<ConductorTripsTab> {
  Map<String, dynamic>? _manifestData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadManifest();
    });
  }

  Future<void> _loadManifest() async {
    final tripsState = ref.read(tripsProvider);
    final tripsNotifier = ref.read(tripsProvider.notifier);
    final bookingsNotifier = ref.read(bookingsProvider.notifier);

    if (tripsState.trips.isEmpty) {
      await tripsNotifier.loadTrips();
    }
    final trips = ref.read(tripsProvider).trips;
    if (trips.isNotEmpty) {
      final activeTrip = trips.first;
      final tripId = activeTrip['id'].toString();
      setState(() => _isLoading = true);
      final manifest = await bookingsNotifier.fetchTripManifest(tripId);
      if (mounted) {
        setState(() {
          _manifestData = manifest;
          _isLoading = false;
        });
      }
    }
  }

  String _formatRemainingTime(int totalMinutes) {
    if (totalMinutes < 0) return '0m';
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return '${hours}h ${mins}m';
    }
    return '${totalMinutes}m';
  }

  Future<void> _toggleSeatBoarding(String seat) async {
    final tripsState = ref.read(tripsProvider);
    final bookingsNotifier = ref.read(bookingsProvider.notifier);
    if (tripsState.trips.isEmpty) return;
    final tripId = tripsState.trips.first['id'].toString();
    
    try {
      final updatedBoarded = await bookingsNotifier.toggleBoarding(tripId, seat);
      if (updatedBoarded != null && mounted) {
        setState(() {
          if (_manifestData != null) {
            _manifestData!['boarded_seats'] = updatedBoarded;
          }
        });
        SeatyNotifications.show(
          context,
          updatedBoarded.contains(seat)
              ? 'Seat $seat marked as BOARDED'
              : 'Seat $seat marked as UNBOARDED',
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().replaceFirst('Exception: ', '');
        SeatyNotifications.show(
          context,
          errorMsg,
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripsState = ref.watch(tripsProvider);
    final activeTrip = tripsState.trips.isNotEmpty ? tripsState.trips.first : null;

    final String routeTitle = activeTrip != null
        ? '${activeTrip['origin']} → ${activeTrip['destination']}'
        : 'No Scheduled Route';
    final String busReg = activeTrip?['reg'] ?? 'N/A';
    final int capacity = activeTrip?['total_seats'] ?? 40;

    final List<dynamic> bookedSeats = activeTrip?['booked_seats'] ?? [];
    final List<dynamic> manifestList = _manifestData?['manifest'] ?? [];
    final List<dynamic> boardedList =
        _manifestData?['boarded_seats'] ?? (activeTrip?['boarded_seats'] ?? []);

    final int boardedCount = boardedList.length;
    final int totalBooked = bookedSeats.isNotEmpty ? bookedSeats.length : manifestList.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Heading
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 12),
                child: BoldGradientHeroHeading(
                  title: 'Seat Manifest',
                  subtitle: 'Real-time passenger manifest & seating status.',
                ),
              ),
              const SizedBox(height: 16),

              // Bus & Trip Summary Header Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              routeTitle,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bus: $busReg • Capacity: $capacity Seats',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$boardedCount / $totalBooked',
                          style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Seat Legend Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildLegendItem('Boarded', const Color(0xFF10B981)),
                    _buildLegendItem('Booked', const Color(0xFF2563EB)),
                    _buildLegendItem('Locked', const Color(0xFF94A3B8)),
                    _buildLegendItem('Available', const Color(0xFFCBD5E1)),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Passenger Seat Manifest List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _isLoading
                    ? Column(
                        children: List.generate(
                          5,
                          (index) => const ManifestSkeleton(),
                        ),
                      )
                    : manifestList.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(32),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Column(
                              children: [
                                Icon(
                                  Icons.event_seat_outlined,
                                  size: 36,
                                  color: Color(0xFF94A3B8),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'No confirmed passenger bookings for this trip yet.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: manifestList.length,
                            separatorBuilder: (ctx, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, index) {
                              final item = manifestList[index] as Map<String, dynamic>;
                              final seat = item['seat']?.toString() ?? 'N/A';
                              final isBoarded = boardedList.contains(seat);
                              
                              final departureStr = activeTrip?['departure'];
                              bool isBoardingAvailable = true;
                              String disabledReason = "";
                              if (departureStr != null) {
                                try {
                                  final departureTime = DateTime.parse(departureStr.replaceAll(' ', 'T'));
                                  final now = DateTime.now();
                                  final difference = departureTime.difference(now);
                                  if (difference.inMinutes > 30) {
                                    isBoardingAvailable = false;
                                    disabledReason = "Boarding is only allowed within 30 minutes of the ride. Departure is in ${_formatRemainingTime(difference.inMinutes)} (at $departureStr).";
                                  }
                                } catch (e) {
                                  debugPrint('Error parsing departure: $e');
                                }
                              }
                              
                              final isLocked = !isBoarded && !isBoardingAvailable;
                              final status = isBoarded 
                                  ? 'BOARDED' 
                                  : isLocked
                                      ? 'LOCKED'
                                      : 'BOOKED';
                              final Color statusColor = isBoarded
                                  ? const Color(0xFF10B981)
                                  : isLocked
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF2563EB);

                              final genderStr = (item['gender'] ?? '').toString();

                              return InkWell(
                                onTap: () {
                                  if (isLocked) {
                                    SeatyNotifications.show(
                                      context,
                                      disabledReason,
                                      isError: true,
                                    );
                                    return;
                                  }
                                  _toggleSeatBoarding(seat);
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isLocked ? const Color(0xFFF8FAFC) : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFF1F5F9),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Text(
                                            seat,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: statusColor,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item['name'] ?? 'Passenger',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: isLocked ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Phone: ${item['phone'] ?? 'N/A'} ${genderStr.isNotEmpty ? '• ${genderStr.toUpperCase()}' : ''}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isLocked) ...[
                                              const Icon(
                                                Icons.lock_outline_rounded,
                                                size: 10,
                                                color: Color(0xFF94A3B8),
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                            Text(
                                              status,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
