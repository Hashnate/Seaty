import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../profile_screen.dart';
import 'owner_home_tab.dart';
import 'fleet_crew_screen.dart';
import 'trip_operations_screen.dart';

class OwnerMainScreen extends ConsumerStatefulWidget {
  const OwnerMainScreen({super.key});

  @override
  ConsumerState<OwnerMainScreen> createState() => _OwnerMainScreenState();
}

class _OwnerMainScreenState extends ConsumerState<OwnerMainScreen> {
  int _currentIndex = 0;
  int _fleetCrewSubTab = 0;
  int _tripOpsSubTab = 0;

  void _navigateToSection(int navIndex, int subTab) {
    setState(() {
      _currentIndex = navIndex;
      if (navIndex == 1) _fleetCrewSubTab = subTab;
      if (navIndex == 2) _tripOpsSubTab = subTab;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      OwnerHomeTab(onNavigate: _navigateToSection),
      FleetCrewScreen(
        key: ValueKey('fleet_crew_$_fleetCrewSubTab'),
        initialSubTab: _fleetCrewSubTab,
      ),
      TripOperationsScreen(
        key: ValueKey('trip_ops_$_tripOpsSubTab'),
        initialSubTab: _tripOpsSubTab,
      ),
      const ProfileEditScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      // AppBar is handled by each screen individually to prevent duplicate headers
      body: tabs[_currentIndex],
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(left: 32, right: 32, bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Premium Dark Slate
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
            _buildNavItem(
              1,
              Icons.directions_bus_outlined,
              Icons.directions_bus_rounded,
              'Manage',
            ),
            _buildNavItem(
              2,
              Icons.route_outlined,
              Icons.route_rounded,
              'Operations',
            ),
            _buildNavItem(
              3,
              Icons.person_outline_rounded,
              Icons.person_rounded,
              'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData outlineIcon,
    IconData solidIcon,
    String label,
  ) {
    final isSelected = _currentIndex == index;
    final activeColor = Colors.white;
    final activeBgColor = const Color(0xFF2563EB); // Matte Orange
    final inactiveColor = Colors.white.withOpacity(0.5);

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuint,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuint,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? solidIcon : outlineIcon,
                color: isSelected ? activeColor : inactiveColor,
                size: 24,
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
