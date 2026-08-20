import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:seaty/main.dart';
import 'package:seaty/screens/payment_webview_screen.dart';
import 'package:seaty/widgets/seaty_bus_loading.dart';
import 'package:seaty/widgets/seaty_notifications.dart';

/// Screen displayed after passenger inputs details and before launching payment.
/// Gives users a complete overview of their trip, seats, passenger info, and fare breakdown.
class BookingOverviewScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> trip;
  final Map<String, dynamic> passengerDetails;
  final List<String> selectedSeats;
  final double totalPrice;

  const BookingOverviewScreen({
    super.key,
    required this.trip,
    required this.passengerDetails,
    required this.selectedSeats,
    required this.totalPrice,
  });

  @override
  ConsumerState<BookingOverviewScreen> createState() => _BookingOverviewScreenState();
}

class _BookingOverviewScreenState extends ConsumerState<BookingOverviewScreen> {
  bool _isProcessing = false;

  void _proceedToPayment(double calculatedTotal) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final bookingsNotifier = ref.read(bookingsProvider.notifier);
    final tripId = widget.trip['id']?.toString() ?? '';

    // 1. Create booking (Pending status)
    final booking = await bookingsNotifier.initiateBooking(
      tripId,
      widget.passengerDetails,
    );

    if (booking == null) {
      if (mounted) {
        setState(() => _isProcessing = false);
        SeatyNotifications.show(
          context,
          bookingsNotifier.lastErrorMessage ??
              'Failed to hold seats. They may have just been booked.',
          isError: true,
        );
      }
      return;
    }

    // 2. Initiate payment session
    final payment = await bookingsNotifier.initiatePayment(booking['id'].toString());
    if (payment == null) {
      if (mounted) {
        setState(() => _isProcessing = false);
        SeatyNotifications.show(
          context,
          bookingsNotifier.lastErrorMessage ??
              'Failed to initiate payment session.',
          isError: true,
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isProcessing = false);

    // 3. Hand off to the gateway's hosted page
    final outcome = await startPaymentFlow(
      context,
      ref,
      paymentUrl: payment['payment_url']?.toString() ?? '',
      bookingId: booking['id'].toString(),
      amount: (payment['amount'] as num?)?.toDouble() ?? calculatedTotal,
    );

    if (!mounted) return;
    showPaymentOutcome(context, outcome);

    if (outcome == PaymentOutcome.success) {
      // Pop all the way back to main screen where Ticket screen is accessible
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final primary = widget.passengerDetails['primary'] as Map<String, dynamic>? ?? {};
    final guests = (widget.passengerDetails['guests'] as List<dynamic>?) ?? [];

    final busName = trip['bus_name'] ?? trip['name'] ?? 'Express Bus';
    final regNo = trip['reg'] ?? trip['registration_number'] ?? '';
    final origin = trip['origin'] ?? 'Origin';
    final destination = trip['destination'] ?? 'Destination';
    final departureRaw = trip['departure']?.toString() ?? '';
    final arrivalRaw = trip['arrival']?.toString() ?? '';
    final rating = trip['rating'] ?? trip['average_rating'];

    // Format Departure Date and Time
    String depDate = '';
    String depTime = '';
    if (departureRaw.isNotEmpty) {
      final dt = DateTime.tryParse(departureRaw.replaceAll(' ', 'T'));
      if (dt != null) {
        depTime = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        depDate = '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
      } else {
        depTime = departureRaw;
      }
    }

    // Format Arrival Time
    String arrTime = '';
    if (arrivalRaw.isNotEmpty) {
      final dt = DateTime.tryParse(arrivalRaw.replaceAll(' ', 'T'));
      if (dt != null) {
        arrTime = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        arrTime = arrivalRaw;
      }
    }

    // Fare & Platform Service Fee calculations matching backend: (subtotal * 3.0%) + 25.00 LKR
    final int seatCount = widget.selectedSeats.isNotEmpty ? widget.selectedSeats.length : 1;
    final double pricePerSeat = (trip['price'] as num?)?.toDouble() ?? 1600.0;
    final double baseFare = pricePerSeat * seatCount;
    final double serviceFee = (baseFare * 0.03) + 25.0;
    final double totalPayable = baseFare + serviceFee;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF0F172A),
              size: 16,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Review Booking',
              style: TextStyle(
                color: Color(0xFF0A2540),
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Please verify details before payment',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Trip & Journey Overview Card ──
            _buildTripCard(
              busName: busName,
              regNo: regNo,
              origin: origin,
              destination: destination,
              depDate: depDate,
              depTime: depTime,
              arrTime: arrTime,
              rating: rating,
              amenities: List<String>.from(trip['amenities'] ?? []),
            ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),

            const SizedBox(height: 16),

            // ── 2. Seats & Passenger Details Card ──
            _buildPassengerAndSeatsCard(
              selectedSeats: widget.selectedSeats,
              primary: primary,
              guests: guests,
            ).animate().fadeIn(delay: 100.ms, duration: 350.ms).slideY(begin: 0.05, end: 0),

            const SizedBox(height: 16),

            // ── 3. Price & Fare Breakdown Card ──
            _buildFareBreakdownCard(
              seatCount: seatCount,
              pricePerSeat: pricePerSeat,
              baseFare: baseFare,
              serviceFee: serviceFee,
              totalPayable: totalPayable,
            ).animate().fadeIn(delay: 200.ms, duration: 350.ms).slideY(begin: 0.05, end: 0),

            const SizedBox(height: 16),

            // ── 4. Boarding Notice Card ──
            _buildBoardingNoticeCard()
                .animate()
                .fadeIn(delay: 300.ms, duration: 350.ms)
                .slideY(begin: 0.05, end: 0),
          ],
        ),
      ),

      // ── Sticky Bottom Action Bar ──
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0A2540).withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              // Total Fare Column
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL FARE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'LKR ${totalPayable.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0A2540),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Pay Now CTA Button
              Expanded(
                flex: 6,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : () => _proceedToPayment(totalPayable),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isProcessing
                        ? const Center(
                            child: SeatyBusLoadingIndicator.small(
                              busColor: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Proceed to Pay',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Card 1: Trip & Route Details ──
  Widget _buildTripCard({
    required String busName,
    required String regNo,
    required String origin,
    required String destination,
    required String depDate,
    required String depTime,
    required String arrTime,
    dynamic rating,
    required List<String> amenities,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A2540).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.directions_bus_rounded,
                    color: Color(0xFF2563EB),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        busName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0A2540),
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (regNo.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          regNo,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (rating != null && (rating is num && rating > 0))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          rating.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Departure Date banner
          if (depDate.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    depDate,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            ),

          // Route Nodes
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Origin
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        depTime.isNotEmpty ? depTime : 'Departure',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0A2540),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        origin,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow Indicator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF94A3B8),
                    size: 20,
                  ),
                ),

                // Destination
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        arrTime.isNotEmpty ? arrTime : 'Arrival',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0A2540),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        destination,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Amenities chips (if any)
          if (amenities.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: amenities.take(4).map((a) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 12,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          a,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Card 2: Passenger & Seat Allocation ──
  Widget _buildPassengerAndSeatsCard({
    required List<String> selectedSeats,
    required Map<String, dynamic> primary,
    required List<dynamic> guests,
  }) {
    final name = primary['name']?.toString() ?? 'Passenger';
    final phone = primary['phone']?.toString() ?? '';
    final nic = primary['nic']?.toString() ?? '';
    final gender = primary['gender']?.toString() ?? 'Male';
    final bookingType = primary['booking_type']?.toString() ?? 'self';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A2540).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Passenger & Seats',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0A2540),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${selectedSeats.length} ${selectedSeats.length == 1 ? 'Seat' : 'Seats'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Selected Seats Badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: selectedSeats.map((seat) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_seat_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Seat $seat',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Primary Passenger Info
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.1),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0A2540),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            gender,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      bookingType == 'self' ? 'Primary Passenger (Self)' : 'Primary Contact',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // NIC and Phone pills
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                if (phone.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_android_rounded,
                        size: 15,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Mobile:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0A2540),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                if (phone.isNotEmpty && nic.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                  ),
                if (nic.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        size: 15,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'NIC Number:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        nic,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0A2540),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Guest allocations if any
          if (guests.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Additional Seat Allocations',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: guests.map((g) {
                final seat = g['seat'] ?? '';
                final gGender = g['gender'] ?? 'Passenger';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Seat $seat: $gGender',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Card 3: Fare & Price Breakdown ──
  Widget _buildFareBreakdownCard({
    required int seatCount,
    required double pricePerSeat,
    required double baseFare,
    required double serviceFee,
    required double totalPayable,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A2540).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Fare Breakdown',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A2540),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Seat Price row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Seat Fare (LKR ${pricePerSeat.toStringAsFixed(0)} × $seatCount)',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'LKR ${baseFare.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0A2540),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Service Fee
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Booking & Service Fee',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'LKR ${serviceFee.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0A2540),
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Payable',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A2540),
                ),
              ),
              Text(
                'LKR ${totalPayable.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Card 4: Boarding Notice & Policy ──
  Widget _buildBoardingNoticeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF2563EB),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Boarding Information',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E40AF),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '• Boarding gates open 30 minutes before departure.\n• Please present your National Identity Card (NIC) with your e-ticket QR code.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF1E3A8A),
                    height: 1.4,
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
