import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/screens/profile_screen.dart';
import 'conductor_home_tab.dart';
import 'conductor_scan_tab.dart';
import 'conductor_trips_tab.dart';

class ConductorMainScreen extends ConsumerStatefulWidget {
  const ConductorMainScreen({super.key});

  @override
  ConsumerState<ConductorMainScreen> createState() =>
      _ConductorMainScreenState();
}

class _ConductorMainScreenState extends ConsumerState<ConductorMainScreen> {
  int _currentIndex = 0;

  void _onNavigate(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      ConductorHomeTab(onNavigate: _onNavigate),
      const ConductorScanTab(),
      const ConductorTripsTab(),
      const ProfileEditScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.only(left: 32, right: 32, bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // Premium Dark Slate
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
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
              Icons.qr_code_scanner_outlined,
              Icons.qr_code_scanner_rounded,
              'Scan',
            ),
            _buildNavItem(
              2,
              Icons.event_seat_outlined,
              Icons.event_seat_rounded,
              'Manifest',
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
    final activeBgColor = const Color(0xFFE65100);
    final inactiveColor = Colors.white.withValues(alpha: 0.5);

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
