import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';

class BusDetailsScreen extends ConsumerWidget {
  final Map<String, dynamic> trip;

  const BusDetailsScreen({super.key, required this.trip});

  Widget _getAmenityIcon(String name, {Color color = const Color(0xFFE65100)}) {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final String priceStr =
        double.tryParse(trip['price'].toString())?.toStringAsFixed(2) ??
        trip['price'].toString();
    final int totalSeats = trip['total_seats'] as int? ?? 40;
    final int bookedCount = (trip['boarded_seats'] as List?)?.length ?? 0;
    final int seatsLeft = totalSeats - bookedCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fixed Top Header Banner (Height: 220px for Bus Image) ──
          Container(
            height: 220,
            width: double.infinity,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Abstract Background Image Placeholder / Gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0A2540), Color(0xFF0E3A5E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Stylized Bus illustration representing owner's uploaded bus photo
                Opacity(
                  opacity: 0.1,
                  child: Center(
                    child: Icon(
                      Icons.directions_bus_rounded,
                      size: 160,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                // Dark overlay to keep text clear
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
                // 2. Safe Area Headers and Titles
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top row: Back Button & Registration tag
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
                                color: const Color(0xFFE65100),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                trip['reg'],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Bottom row: Bus Name & Placeholder Info text
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip['bus_name'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Luxurious ride details • Verified by Seaty',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11,
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

          // ── Scrollable Body Content (Fits details + Passenger reviews) ──
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Journey Details Card ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
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
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.circle_outlined,
                                color: Color(0xFFE65100),
                                size: 14,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trip['origin'],
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0A2540),
                                      ),
                                    ),
                                    Text(
                                      'Departure: ${trip['departure']}',
                                      style: const TextStyle(
                                        fontSize: 10,
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
                            padding: const EdgeInsets.only(left: 6.0),
                            child: Container(
                              width: 2,
                              height: 12,
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFF0A2540),
                                size: 14,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trip['destination'],
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0A2540),
                                      ),
                                    ),
                                    const Text(
                                      'Arrival: Estimated 2 hrs duration',
                                      style: TextStyle(
                                        fontSize: 10,
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
                    const SizedBox(height: 10),

                    // ── Seat Availability Stats ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A2540).withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(
                            0xFF0A2540,
                          ).withValues(alpha: 0.08),
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
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$seatsLeft of $totalSeats Seats Available',
                                style: const TextStyle(
                                  color: Color(0xFF0A2540),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const Row(
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 12,
                                color: Color(0xFF10B981),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Seaty Verified',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Amenities Grid ──
                    if (trip['amenities'] != null &&
                        (trip['amenities'] as List).isNotEmpty) ...[
                      const Text(
                        'Bus Amenities & Services',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0A2540),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 3.5,
                            ),
                        itemCount: (trip['amenities'] as List).length,
                        itemBuilder: (context, index) {
                          final name = trip['amenities'][index].toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                _getAmenityIcon(name),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 10,
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
                      const SizedBox(height: 20),
                    ],

                    // ── Passenger Reviews (Dummy comments section) ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Passenger Reviews',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0A2540),
                            letterSpacing: -0.3,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0A2540,
                            ).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                color: Color(0xFFE65100),
                                size: 12,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '4.8 (12)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0A2540),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Review Item 1
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
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
                                    radius: 12,
                                    backgroundColor: const Color(
                                      0xFFE65100,
                                    ).withValues(alpha: 0.1),
                                    child: const Text(
                                      'S',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFE65100),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Saman Perera',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0A2540),
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                'Yesterday',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: List.generate(5, (index) {
                              return const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFE65100),
                                size: 10,
                              );
                            }),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Very clean seats and arrived exactly on time. Highly recommended!',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Review Item 2
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
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
                                    radius: 12,
                                    backgroundColor: const Color(
                                      0xFF0A2540,
                                    ).withValues(alpha: 0.1),
                                    child: const Text(
                                      'P',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0A2540),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Priyantha J.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0A2540),
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                '3 days ago',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: List.generate(5, (index) {
                              return Icon(
                                Icons.star_rounded,
                                color: index < 4
                                    ? const Color(0xFFE65100)
                                    : const Color(0xFFCBD5E1),
                                size: 10,
                              );
                            }),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Comfortable journey. Air conditioning was perfect and there was plenty of space for bags.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        'You can leave a review after completing your ride.',
                        style: TextStyle(
                          fontSize: 10,
                          color: const Color(0xFF64748B).withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom Action Bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, -6),
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
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'Rs. $priceStr',
                          style: const TextStyle(
                            color: Color(0xFFE65100),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Text(
                          '/ seat',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 10,
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
                      MaterialPageRoute(
                        builder: (context) => SeatSelectorScreen(trip: trip),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2540),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
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
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14),
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
