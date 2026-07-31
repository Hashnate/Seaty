import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/theme/app_theme.dart';

class BusDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> trip;

  const BusDetailsScreen({super.key, required this.trip});

  @override
  ConsumerState<BusDetailsScreen> createState() => _BusDetailsScreenState();
}

class _BusDetailsScreenState extends ConsumerState<BusDetailsScreen> {
  bool _isLoadingReviews = true;
  double _avgRating = 0.0;
  int _totalReviews = 0;
  List<dynamic> _reviewsList = [];

  @override
  void initState() {
    super.initState();
    _loadRealtimeReviews();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tripId = widget.trip['id']?.toString() ?? '';
      if (tripId.isNotEmpty) {
        ref.read(bookingsProvider.notifier).loadSeatAvailability(tripId, clearFirst: true);
      }
    });
  }

  Future<void> _loadRealtimeReviews() async {
    final vehicleId = widget.trip['vehicle_id']?.toString() ?? '';
    if (vehicleId.isEmpty) {
      if (mounted) setState(() => _isLoadingReviews = false);
      return;
    }

    final fleetNotifier = ref.read(fleetProvider.notifier);
    final data = await fleetNotifier.fetchVehicleReviews(vehicleId);

    if (mounted) {
      setState(() {
        _avgRating = (data['average_rating'] as num?)?.toDouble() ?? 0.0;
        _totalReviews = (data['total_reviews'] as num?)?.toInt() ?? 0;
        _reviewsList = (data['reviews'] as List?) ?? [];
        _isLoadingReviews = false;
      });
    }
  }

  void _showWriteReviewModal() {
    int selectedRating = 5;
    final commentCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Write a Review',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0A2540),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share your journey experience on ${widget.trip['bus_name'] ?? 'this bus'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Star Selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starVal = index + 1;
                      return IconButton(
                        icon: Icon(
                          starVal <= selectedRating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: const Color(0xFF2563EB),
                          size: 32,
                        ),
                        onPressed: () {
                          setModalState(() => selectedRating = starVal);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  // Comment TextField
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Describe your ride (comfort, cleanliness, punctuality)...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF0A2540)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final commentText = commentCtrl.text.trim();
                        final vehicleId = widget.trip['vehicle_id']?.toString() ?? '';
                        Navigator.pop(context);

                        if (vehicleId.isEmpty) return;

                        SeatyNotifications.show(
                          context,
                          'Submitting review...',
                          duration: const Duration(milliseconds: 800),
                        );

                        final success = await ref
                            .read(fleetProvider.notifier)
                            .submitVehicleReview(vehicleId, selectedRating, commentText);

                        if (success) {
                          await _loadRealtimeReviews();
                          if (mounted) {
                            SeatyNotifications.show(
                              context,
                              'Thank you! Your review is now live.',
                            );
                          }
                        } else {
                          if (mounted) {
                            SeatyNotifications.show(
                              context,
                              'Failed to submit review.',
                              isError: true,
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Submit Review',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _getAmenityIcon(String name, {Color color = const Color(0xFF2563EB)}) {
    final String n = name.toLowerCase();
    IconData iconData = Icons.star_outline_rounded;

    if (n.contains('wifi')) {
      iconData = Icons.wifi_rounded;
    } else if (n.contains('charge') ||
        n.contains('charging') ||
        n.contains('plug') ||
        n.contains('outlet')) {
      iconData = Icons.power_rounded;
    } else if (n.contains('tv') ||
        n.contains('screen') ||
        n.contains('video') ||
        n.contains('hd tv')) {
      iconData = Icons.tv_rounded;
    } else if (n.contains('seat') ||
        n.contains('recline') ||
        n.contains('reclining')) {
      iconData = Icons.chair_rounded;
    } else if (n.contains('restroom') ||
        n.contains('toilet') ||
        n.contains('wc')) {
      iconData = Icons.wc_rounded;
    } else if (n.contains('luggage') ||
        n.contains('baggage') ||
        n.contains('bag') ||
        n.contains('space')) {
      iconData = Icons.work_rounded;
    } else if (n.contains('ac') ||
        n.contains('air') ||
        n.contains('cool') ||
        n.contains('snowflake')) {
      iconData = Icons.ac_unit_rounded;
    }

    return Icon(iconData, size: 16, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final bookingsState = ref.watch(bookingsProvider);
    final String priceStr =
        double.tryParse(widget.trip['price'].toString())?.toStringAsFixed(2) ??
        widget.trip['price'].toString();
    final int totalSeats = widget.trip['total_seats'] as int? ?? 40;
    final List<dynamic> tripBookedSeats = (widget.trip['booked_seats'] as List?) ?? [];
    final int bookedCount = bookingsState.bookedSeats.isNotEmpty 
        ? bookingsState.bookedSeats.length 
        : tripBookedSeats.length;
    final int seatsLeft = (totalSeats - bookedCount).clamp(0, totalSeats);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fixed Top Header Banner ──
          Container(
            height: 200,
            width: double.infinity,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0A2540), Color(0xFF0E3A5E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                Opacity(
                  opacity: 0.12,
                  child: Center(
                    child: Icon(
                      Icons.directions_bus_rounded,
                      size: 140,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.5),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.trip['reg'] ?? '',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.trip['bus_name'] ?? 'Bus Express',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Luxurious ride details',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable Body Content ──
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Journey Details Card
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'JOURNEY DETAILS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.circle_outlined,
                                color: Color(0xFF2563EB),
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.trip['origin'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0A2540),
                                      ),
                                    ),
                                    Text(
                                      'Departure: ${widget.trip['departure']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 7.0, top: 2, bottom: 2),
                            child: Container(
                              width: 2,
                              height: 12,
                              color: const Color(0xFFCBD5E1),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFF0A2540),
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.trip['destination'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0A2540),
                                      ),
                                    ),
                                    Text(
                                      () {
                                        final departureStr = widget.trip['departure']?.toString() ?? '';
                                        final arrivalStr = widget.trip['arrival']?.toString() ?? '';
                                        if (departureStr.isNotEmpty && arrivalStr.isNotEmpty) {
                                          try {
                                            final dep = DateTime.parse(departureStr.replaceAll(' ', 'T'));
                                            final arr = DateTime.parse(arrivalStr.replaceAll(' ', 'T'));
                                            final diff = arr.difference(dep);
                                            final hours = diff.inHours;
                                            final mins = diff.inMinutes % 60;
                                            if (hours > 0) {
                                              return 'Arrival: Estimated $hours ${hours == 1 ? "hr" : "hrs"}${mins > 0 ? " $mins min" : ""} duration';
                                            } else if (mins > 0) {
                                              return 'Arrival: Estimated $mins min duration';
                                            }
                                          } catch (e) {
                                            debugPrint('Error parsing duration: $e');
                                          }
                                        }
                                        return 'Arrival: Estimated duration';
                                      }(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Seat Availability Stats
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A2540).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF0A2540).withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.event_seat_rounded,
                                color: Color(0xFF0A2540),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$seatsLeft of $totalSeats Seats Available',
                                style: const TextStyle(
                                  color: Color(0xFF0A2540),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox.shrink(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Amenities Grid
                    if (widget.trip['amenities'] != null &&
                        (widget.trip['amenities'] as List).isNotEmpty) ...[
                      const Text(
                        'Bus Amenities & Services',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0A2540),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 2.7,
                            ),
                        itemCount: (widget.trip['amenities'] as List).length,
                        itemBuilder: (context, index) {
                          final name = widget.trip['amenities'][index].toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                _getAmenityIcon(name),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0A2540),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Dynamic Real-Time Passenger Reviews ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Passenger Reviews',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0A2540),
                            letterSpacing: -0.3,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFF2563EB),
                                    size: 15,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${_avgRating > 0 ? _avgRating.toStringAsFixed(1) : "N/A"} ($_totalReviews)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _showWriteReviewModal,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A2540),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.rate_review_rounded,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Review',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_isLoadingReviews)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF2563EB),
                            strokeWidth: 2.5,
                          ),
                        ),
                      )
                    else if (_reviewsList.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.star_outline_rounded,
                              size: 32,
                              color: Color(0xFF94A3B8),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'No reviews yet for this bus.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Be the first passenger to leave a review!',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: _reviewsList.map((item) {
                          final name = (item['passenger_name'] ?? 'Passenger').toString();
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'P';
                          final rating = (item['rating'] as num?)?.toInt() ?? 5;
                          final comment = (item['comment'] ?? '').toString();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: const Color(
                                            0xFF2563EB,
                                          ).withValues(alpha: 0.15),
                                          child: Text(
                                            initial,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2563EB),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0A2540),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Text(
                                      'Verified Passenger',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: List.generate(5, (starIdx) {
                                    return Icon(
                                      Icons.star_rounded,
                                      color: starIdx < rating
                                          ? const Color(0xFF2563EB)
                                          : const Color(0xFFCBD5E1),
                                      size: 14,
                                    );
                                  }),
                                ),
                                if (comment.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    comment,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF334155),
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Action Bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
              border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Total Price',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'Rs. $priceStr',
                          style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          '/ seat',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      SeatyPageRoute(
                        page: SeatSelectorScreen(trip: widget.trip),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2540),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Choose Seat',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 15),
                    ],
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
