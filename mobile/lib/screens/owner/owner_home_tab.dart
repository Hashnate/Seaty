import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';

class OwnerHomeTab extends ConsumerStatefulWidget {
  final Function(int navIndex, int subTab)? onNavigate;
  const OwnerHomeTab({super.key, this.onNavigate});

  @override
  ConsumerState<OwnerHomeTab> createState() => _OwnerHomeTabState();
}

class _OwnerHomeTabState extends ConsumerState<OwnerHomeTab> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final ownerName = state.userName.isNotEmpty ? state.userName : 'Bus Owner';
    final vehicleCount = state.vehicles.isNotEmpty ? state.vehicles.length : 12;
    final conductorCount = state.conductorsList.isNotEmpty
        ? state.conductorsList.length
        : 8;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HEADER ─────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $ownerName 👋',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Dashboard',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.8,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 36,
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE65100), Color(0xFFFF8A65)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: Color(0xFF0F172A),
                        size: 22,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── REVENUE CARD ───────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
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
                          'Monthly Revenue',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
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
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.trending_up_rounded,
                                color: Color(0xFF10B981),
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '+18.4%',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'LKR 485,200',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'From online bookings this month',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),
                    // Mini progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 65,
                            child: Container(
                              height: 4,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFE65100),
                                    Color(0xFFFF8A65),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 35,
                            child: Container(
                              height: 4,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── QUICK STATS ────────────────────────────
              const Text(
                'Overview',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.directions_bus_filled_rounded,
                      iconBg: const Color(0xFF0F172A),
                      value: '$vehicleCount',
                      label: 'Buses',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.badge_rounded,
                      iconBg: const Color(0xFFE65100),
                      value: '$conductorCount',
                      label: 'Conductors',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.route_rounded,
                      iconBg: const Color(0xFF3B82F6),
                      value: '4',
                      label: 'Live Trips',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── ONGOING TRIPS ──────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Ongoing Trips',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (widget.onNavigate != null) {
                        widget.onNavigate!(2, 0);
                      }
                    },
                    child: const Text(
                      'View All',
                      style: TextStyle(
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildTripCard(
                route: 'Colombo → Kandy',
                busReg: 'NC-4821',
                conductor: 'Sunil Perera',
                progress: 0.81,
                passengers: '34/42',
                status: 'EN ROUTE',
                statusColor: const Color(0xFF10B981),
              ),
              const SizedBox(height: 10),
              _buildTripCard(
                route: 'Galle → Fort',
                busReg: 'WP-ND-1234',
                conductor: 'Nimal Silva',
                progress: 1.0,
                passengers: '40/40',
                status: 'FULL',
                statusColor: const Color(0xFF3B82F6),
              ),
              const SizedBox(height: 10),
              _buildTripCard(
                route: 'Matara → Colombo',
                busReg: 'BR-9900',
                conductor: 'Kamal Dias',
                progress: 0.45,
                passengers: '18/40',
                status: 'BOARDING',
                statusColor: const Color(0xFFE65100),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── STAT CARD WIDGET ─────────────────────────
  Widget _buildStatCard({
    required IconData icon,
    required Color iconBg,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  // ── TRIP CARD WIDGET ─────────────────────────
  Widget _buildTripCard({
    required String route,
    required String busReg,
    required String conductor,
    required double progress,
    required String passengers,
    required String status,
    required Color statusColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: route + status badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.directions_bus_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            route,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Bus: $busReg • $conductor',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                passengers,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
