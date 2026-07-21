import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/screens/tracker_screen.dart';

class ConductorTripsTab extends ConsumerStatefulWidget {
  const ConductorTripsTab({super.key});

  @override
  ConsumerState<ConductorTripsTab> createState() => _ConductorTripsTabState();
}

class _ConductorTripsTabState extends ConsumerState<ConductorTripsTab> {
  // Demo Seat Manifest layout data
  final List<Map<String, dynamic>> _passengerSeats = [
    {'seat': '01A', 'name': 'Kusal Perera', 'status': 'BOARDED', 'gender': 'M'},
    {'seat': '01B', 'name': 'Nimali Silva', 'status': 'BOARDED', 'gender': 'F'},
    {'seat': '02A', 'name': 'Kamal Dias', 'status': 'BOOKED', 'gender': 'M'},
    {'seat': '02B', 'name': 'Sunil Shantha', 'status': 'BOARDED', 'gender': 'M'},
    {'seat': '03A', 'name': 'Anusha Fernando', 'status': 'BOOKED', 'gender': 'F'},
    {'seat': '03B', 'name': 'Empty', 'status': 'AVAILABLE', 'gender': ''},
    {'seat': '04A', 'name': 'Mohamed Muzakkir', 'status': 'BOARDED', 'gender': 'M'},
    {'seat': '04B', 'name': 'Fathima Razi', 'status': 'BOARDED', 'gender': 'F'},
  ];

  @override
  Widget build(BuildContext context) {
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Colombo → Kandy Express',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Bus: NC-4821 • Capacity: 42 Seats',
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '34 / 42',
                          style: TextStyle(
                            color: Color(0xFFE65100),
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
                    _buildLegendItem('Booked', const Color(0xFFE65100)),
                    _buildLegendItem('Available', const Color(0xFFCBD5E1)),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Passenger Seat Manifest List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _passengerSeats.length,
                  separatorBuilder: (ctx, index) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final item = _passengerSeats[index];
                    final status = item['status'] as String;
                    Color statusColor = const Color(0xFFCBD5E1);
                    if (status == 'BOARDED') statusColor = const Color(0xFF10B981);
                    if (status == 'BOOKED') statusColor = const Color(0xFFE65100);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                item['seat'],
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: statusColor == const Color(0xFFCBD5E1)
                                      ? const Color(0xFF64748B)
                                      : statusColor,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                if (item['gender'].isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Gender: ${item['gender'] == 'M' ? 'Male' : 'Female'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: statusColor == const Color(0xFFCBD5E1)
                                    ? const Color(0xFF64748B)
                                    : statusColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
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
