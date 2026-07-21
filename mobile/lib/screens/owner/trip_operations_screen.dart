import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/screens/tracker_screen.dart';

class TripOperationsScreen extends ConsumerStatefulWidget {
  final int initialSubTab;
  const TripOperationsScreen({super.key, this.initialSubTab = 0});

  @override
  ConsumerState<TripOperationsScreen> createState() =>
      _TripOperationsScreenState();
}

class _TripOperationsScreenState extends ConsumerState<TripOperationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _selectedBus = 'NC-4821';
  final Set<int> _vipReservedSeats = {1, 2, 3, 4};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialSubTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // PROFILE-STYLE BOLD GRADIENT HERO HEADING
            const Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 12),
              child: BoldGradientHeroHeading(
                title: 'Trip Operations',
                subtitle: '',
              ),
            ),
            const SizedBox(height: 12),

            // TAB BAR SWITCHER
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFE65100),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFFE65100),
              indicatorWeight: 3,
              dividerHeight: 0,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.calendar_month_rounded),
                  text: 'Scheduling Dispatch',
                ),
                Tab(
                  icon: Icon(Icons.event_seat_rounded),
                  text: 'Seat Allocations',
                ),
              ],
            ),

            // TAB BAR VIEW
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // SUB-TAB 1: SCHEDULING DISPATCH
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildScheduleCard(
                          route: 'Route 01: Colombo ➔ Kandy',
                          bus: 'NC-4821',
                          time: '06:30 AM',
                          freq: 'Daily',
                          status: 'ON TIME',
                          statusColor: const Color(0xFF10B981),
                        ),
                        _buildScheduleCard(
                          route: 'Route 05: Galle ➔ Fort',
                          bus: 'WP-ND-1234',
                          time: '08:00 AM',
                          freq: 'Daily',
                          status: 'BOARDING',
                          statusColor: const Color(0xFF3B82F6),
                        ),
                        _buildScheduleCard(
                          route: 'Route 12: Jaffna ➔ Colombo',
                          bus: 'BR-9900',
                          time: '09:30 PM',
                          freq: 'Night Express',
                          status: 'SCHEDULED',
                          statusColor: const Color(0xFF8B5CF6),
                        ),
                      ],
                    ),
                  ),

                  // SUB-TAB 2: SEAT ALLOCATIONS
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.directions_bus_rounded,
                                    color: Color(0xFF0A2540),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Select Bus:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              DropdownButton<String>(
                                value: _selectedBus,
                                underline: const SizedBox(),
                                items: ['NC-4821', 'WP-ND-1234', 'BR-9900'].map(
                                  (b) {
                                    return DropdownMenuItem(
                                      value: b,
                                      child: Text(
                                        b,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  },
                                ).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedBus = val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Legend Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildLegendTile(Colors.green, 'Available'),
                            _buildLegendTile(const Color(0xFFE65100), 'Booked'),
                            _buildLegendTile(
                              const Color(0xFF3B82F6),
                              'VIP Reserve',
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Visual Seat Grid Layout (40 seats)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              children: [
                                // Driver Cabin Header
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Icon(
                                          Icons.drive_eta_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'DRIVER CABIN',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: GridView.builder(
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: 40,
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 4,
                                          mainAxisSpacing: 10,
                                          crossAxisSpacing: 10,
                                          childAspectRatio: 1.2,
                                        ),
                                    itemBuilder: (context, index) {
                                      final seatNo = index + 1;
                                      final isVip = _vipReservedSeats.contains(
                                        seatNo,
                                      );
                                      final isBooked =
                                          seatNo > 4 && seatNo <= 24;

                                      Color seatBg = Colors.green.shade100;
                                      Color textClr = Colors.green.shade900;

                                      if (isVip) {
                                        seatBg = const Color(
                                          0xFF3B82F6,
                                        ).withOpacity(0.2);
                                        textClr = const Color(0xFF3B82F6);
                                      } else if (isBooked) {
                                        seatBg = const Color(
                                          0xFFE65100,
                                        ).withOpacity(0.2);
                                        textClr = const Color(0xFFE65100);
                                      }

                                      return GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (_vipReservedSeats.contains(
                                              seatNo,
                                            )) {
                                              _vipReservedSeats.remove(seatNo);
                                              SeatyNotifications.show(
                                                context,
                                                'Seat $seatNo un-reserved',
                                              );
                                            } else {
                                              _vipReservedSeats.add(seatNo);
                                              SeatyNotifications.show(
                                                context,
                                                'Seat $seatNo marked as VIP Reserve',
                                              );
                                            }
                                          });
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          decoration: BoxDecoration(
                                            color: seatBg,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: textClr.withOpacity(0.5),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.event_seat_rounded,
                                                  color: textClr,
                                                  size: 18,
                                                ),
                                                Text(
                                                  '$seatNo',
                                                  style: TextStyle(
                                                    color: textClr,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard({
    required String route,
    required String bus,
    required String time,
    required String freq,
    required String status,
    required Color statusColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2540).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.alt_route_rounded,
                color: Color(0xFF0A2540),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Bus: $bus • Time: $time • $freq',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendTile(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
