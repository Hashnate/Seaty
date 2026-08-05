import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/theme/app_colors.dart';
import 'package:seaty/screens/tracker_screen.dart';
import 'package:seaty/screens/ticket_screen.dart';
import 'package:seaty/screens/profile_screen.dart';
import 'package:seaty/screens/bus_details_screen.dart';
import 'package:seaty/screens/notifications_screen.dart';
import 'package:seaty/widgets/shimmer_loading.dart';

// =====================================================================
// 4. PASSENGER MAIN SCREEN
// =====================================================================
class PassengerMainScreen extends ConsumerStatefulWidget {
  const PassengerMainScreen({super.key});

  @override
  ConsumerState<PassengerMainScreen> createState() =>
      _PassengerMainScreenState();
}

class _PassengerMainScreenState extends ConsumerState<PassengerMainScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const PassengerTripsTab(),
    const PassengerTrackingTab(),
    const PassengerBookingsTab(),
    const ProfileEditScreen(),
    const NotificationsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      extendBody: true, // Let content scroll behind the floating capsule
      extendBodyBehindAppBar: true,
      body: _tabs[_currentIndex],
      bottomNavigationBar: _buildTelegramBottomNavBar(context),
    );
  }

  Widget _buildTelegramBottomNavBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
          _buildNavItem(
            1,
            Icons.near_me_outlined,
            Icons.near_me_rounded,
            'Tracker',
          ),
          _buildNavItem(
            2,
            Icons.receipt_long_outlined,
            Icons.receipt_long_rounded,
            'Tickets',
          ),
          _buildNavItem(
            3,
            Icons.person_outline_rounded,
            Icons.person_rounded,
            'Profile',
          ),
          _buildNavItem(
            4,
            Icons.notifications_none_rounded,
            Icons.notifications_rounded,
            'Alerts',
          ),
        ],
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
    final inactiveColor = Colors.white.withOpacity(0.75);

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

// Sub-Tab 1: Passenger Trips & Booking Flow
class PassengerTripsTab extends ConsumerStatefulWidget {
  const PassengerTripsTab({super.key});

  @override
  ConsumerState<PassengerTripsTab> createState() => _PassengerTripsTabState();
}

class _PassengerTripsTabState extends ConsumerState<PassengerTripsTab>
    with WidgetsBindingObserver {
  String _selectedFrom = '';
  String _selectedTo = '';
  DateTime? _selectedDate;

  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final TextEditingController _dateController;
  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();
  final LayerLink _fromLayerLink = LayerLink();
  final LayerLink _toLayerLink = LayerLink();

  late final PageController _heroPageController;
  Timer? _heroSliderTimer;
  int _heroImageIndex = 0;
  late final ScrollController _scrollController;
  double _headerOpacity = 0.0;

  final List<String> _heroImages = [
    'assets/images/bus_slider_1.png',
    'assets/images/bus_slider_2.png',
    'assets/images/bus_slider_3.png',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    _fromController = TextEditingController(text: _selectedFrom);
    _toController = TextEditingController(text: _selectedTo);
    _dateController = TextEditingController(text: 'All Dates');
    _fromFocusNode.addListener(_onFocusChange);
    _toFocusNode.addListener(_onFocusChange);
    _heroPageController = PageController();
    _startHeroSliderTimer();
  }

  void _startHeroSliderTimer() {
    _heroSliderTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      if (_heroPageController.hasClients) {
        final nextPage = (_heroImageIndex + 1) % _heroImages.length;
        _heroPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final newOpacity = (offset / 100.0).clamp(0.0, 1.0);
    if (newOpacity != _headerOpacity) {
      setState(() {
        _headerOpacity = newOpacity;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _heroSliderTimer?.cancel();
    _heroPageController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _dateController.dispose();
    _fromFocusNode.removeListener(_onFocusChange);
    _toFocusNode.removeListener(_onFocusChange);
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    super.dispose();
  }





  @override
  Widget build(BuildContext context) {
    final tripsState = ref.watch(tripsProvider);
    final notificationsState = ref.watch(notificationsProvider);

    final allTrips = tripsState.trips;
    final Set<String> placesSet = {'All'};
    for (final trip in allTrips) {
      if (trip['origin'] != null) placesSet.add(trip['origin'].toString());
      if (trip['destination'] != null)
        placesSet.add(trip['destination'].toString());
      final routeObj = trip['route'];
      if (routeObj != null && routeObj['stops'] != null) {
        for (final stop in routeObj['stops'] as List<dynamic>) {
          final stopName = stop['name']?.toString();
          if (stopName != null) placesSet.add(stopName);
        }
      }
    }
    final List<String> allPlaces = placesSet.toList()
      ..sort((a, b) {
        if (a == 'All') return -1;
        if (b == 'All') return 1;
        return a.compareTo(b);
      });

    final favsState = ref.watch(favouritesProvider);

    final filteredTrips = tripsState.trips.where((trip) {
      final hasFrom =
          _selectedFrom.isNotEmpty && _selectedFrom.toLowerCase() != 'all';
      final hasTo =
          _selectedTo.isNotEmpty && _selectedTo.toLowerCase() != 'all';
      final hasDate = _selectedDate != null;
      if (!hasFrom && !hasTo && !hasDate) return true;

      // Helper to find position of a location (-1 = origin, index = stop index, 100000 = destination)
      int? findStopPos(String searchLoc) {
        final normSearch = searchLoc.toLowerCase().trim();
        if (normSearch.isEmpty) return null;
        final normOrigin = trip['origin']?.toString().toLowerCase() ?? '';
        final normDest = trip['destination']?.toString().toLowerCase() ?? '';

        if (normOrigin.contains(normSearch)) return -1;

        // Check intermediate stops if route details are present
        final routeObj = trip['route'];
        if (routeObj != null && routeObj['stops'] != null) {
          final stops = routeObj['stops'] as List<dynamic>;
          for (int i = 0; i < stops.length; i++) {
            final stopName = stops[i]['name']?.toString().toLowerCase() ?? '';
            if (stopName.contains(normSearch)) {
              return i;
            }
          }
        }

        if (normDest.contains(normSearch)) return 100000;
        return null;
      }

      bool match = true;
      int? fromPos;
      int? toPos;

      if (hasFrom) {
        fromPos = findStopPos(_selectedFrom);
        if (fromPos == null) match = false;
      }

      if (hasTo) {
        toPos = findStopPos(_selectedTo);
        if (toPos == null) match = false;
      }

      // Ensure origin comes before destination
      if (match && hasFrom && hasTo) {
        if (fromPos != null && toPos != null && fromPos >= toPos) {
          match = false;
        }
      }

      // Filter by date if specified
      if (match && hasDate) {
        final departureStr = trip['departure']?.toString() ?? '';
        if (departureStr.isNotEmpty) {
          try {
            final datePart = departureStr
                .split(' ')[0]
                .trim(); // e.g., '2026-07-13'
            final selectedDateStr =
                "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";
            if (datePart != selectedDateStr) {
              match = false;
            }
          } catch (e) {
            match = false;
          }
        } else {
          match = false;
        }
      }

      return match;
    }).toList()
      ..sort((a, b) {
        final bool aFav = favsState.isFavourite(
          vehicleId: a['vehicle_id']?.toString(),
          scheduleId: a['schedule_id']?.toString(),
        );
        final bool bFav = favsState.isFavourite(
          vehicleId: b['vehicle_id']?.toString(),
          scheduleId: b['schedule_id']?.toString(),
        );
        if (aFav && !bFav) return -1;
        if (!aFav && bFav) return 1;
        return 0;
      });

    final double topPadding = MediaQuery.of(context).padding.top;
    final double heroHeight = 310.0 + topPadding;

    final double cardWidth = MediaQuery.of(context).size.width - 40;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            // ─── Fixed Non-Scrollable Auto-Sliding 3-Image Carousel Hero Header ───
            SizedBox(
              height: heroHeight,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. Full-bleed Auto-sliding 3-Image Carousel Background (3s interval)
                    PageView.builder(
                      controller: _heroPageController,
                      itemCount: _heroImages.length,
                      onPageChanged: (index) {
                        setState(() {
                          _heroImageIndex = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        return Image.asset(
                          _heroImages[index],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: const Color(0xFF0F172A),
                            child: const Center(
                              child: Icon(
                                Icons.directions_bus_rounded,
                                color: Colors.white24,
                                size: 64,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Sheer Gradient Overlay for contrast while preserving 100% image visibility
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.55),
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.6),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),

                    // 2. Fixed App Bar (Seaty logo & Bell icon)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Image.asset(
                                    'assets/images/app_icon.png',
                                    width: 28,
                                    height: 28,
                                    color: Colors.white,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.directions_bus_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Seaty',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 3. Welcome text (brought VERY CLOSE to cart) + Search Card
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text(
                              'Where are you traveling today?',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.4,
                                shadows: [
                                  Shadow(blurRadius: 6, color: Colors.black54, offset: Offset(0, 1)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Main Search Input Card ("from to card") - Anchored at bottom of image
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_selectedFrom.isNotEmpty || _selectedTo.isNotEmpty || _selectedDate != null) ...[
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      child: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _selectedFrom = '';
                                            _selectedTo = '';
                                            _selectedDate = null;
                                            _fromController.text = '';
                                            _toController.text = '';
                                            _dateController.text = 'All Dates';
                                          });
                                          ref.read(tripsProvider.notifier).loadTrips();
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          backgroundColor: Colors.black.withValues(alpha: 0.5),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text(
                                          'Clear all filters',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],

                                // Glassmorphic / Clean White Search Card
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.96),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white, width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.18),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // From & To Inputs + Swap Button
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Column(
                                            children: [
                                              CompositedTransformTarget(
                                                link: _fromLayerLink,
                                                child: _buildSearchInputRow(
                                                  icon: Icons.directions_bus_filled_outlined,
                                                  hint: 'From',
                                                  controller: _fromController,
                                                  focusNode: _fromFocusNode,
                                                  onChanged: (val) {
                                                    setState(() {
                                                      _selectedFrom = val;
                                                    });
                                                  },
                                                  onTap: () {
                                                    if (_fromController.text == 'All') {
                                                      _fromController.clear();
                                                      setState(() {
                                                        _selectedFrom = '';
                                                      });
                                                    }
                                                  },
                                                ),
                                              ),
                                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                              CompositedTransformTarget(
                                                link: _toLayerLink,
                                                child: _buildSearchInputRow(
                                                  icon: Icons.directions_bus_filled_outlined,
                                                  hint: 'To',
                                                  controller: _toController,
                                                  focusNode: _toFocusNode,
                                                  onChanged: (val) {
                                                    setState(() {
                                                      _selectedTo = val;
                                                    });
                                                  },
                                                  onTap: () {
                                                    if (_toController.text == 'All') {
                                                      _toController.clear();
                                                      setState(() {
                                                        _selectedTo = '';
                                                      });
                                                    }
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                          Positioned(
                                            right: 16,
                                            top: 27,
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  final temp = _selectedFrom;
                                                  _selectedFrom = _selectedTo;
                                                  _selectedTo = temp;
                                                  _fromController.text = _selectedFrom;
                                                  _toController.text = _selectedTo;
                                                });
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(7),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withValues(alpha: 0.1),
                                                      blurRadius: 4,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.swap_vert_rounded,
                                                  color: Color(0xFF2563EB),
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 1, color: Color(0xFFE2E8F0)),

                                      // Date Row
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.calendar_month_outlined,
                                              color: Color(0xFF64748B),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () async {
                                                  final DateTime? picked = await showDatePicker(
                                                    context: context,
                                                    initialDate: _selectedDate ?? DateTime.now(),
                                                    firstDate: DateTime.now().subtract(const Duration(days: 305)),
                                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                                  );
                                                  if (picked != null) {
                                                    final dateStr = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                                                    setState(() {
                                                      _selectedDate = picked;
                                                      _dateController.text = dateStr;
                                                    });
                                                    ref.read(tripsProvider.notifier).loadTrips(date: dateStr);
                                                  }
                                                },
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Date of journey',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF64748B),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      _formatDateOfJourney(_selectedDate),
                                                      style: const TextStyle(
                                                        color: Color(0xFF0F172A),
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _buildDateQuickPill('Today', () {
                                                  final now = DateTime.now();
                                                  final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
                                                  setState(() {
                                                    _selectedDate = now;
                                                    _dateController.text = dateStr;
                                                  });
                                                  ref.read(tripsProvider.notifier).loadTrips(date: dateStr);
                                                }),
                                                const SizedBox(width: 6),
                                                _buildDateQuickPill('Tomorrow', () {
                                                  final tomorrow = DateTime.now().add(const Duration(days: 1));
                                                  final dateStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";
                                                  setState(() {
                                                    _selectedDate = tomorrow;
                                                    _dateController.text = dateStr;
                                                  });
                                                  ref.read(tripsProvider.notifier).loadTrips(date: dateStr);
                                                }),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Red Search Buses Button inside slider container
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      _fromFocusNode.unfocus();
                                      _toFocusNode.unfocus();
                                      final dateStr = _selectedDate != null
                                          ? "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}"
                                          : null;
                                      ref.read(tripsProvider.notifier).loadTrips(date: dateStr);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Searching buses from $_selectedFrom to $_selectedTo...'),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEF4444),
                                      foregroundColor: Colors.white,
                                      elevation: 4,
                                      shadowColor: Colors.black45,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.search_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'Search buses',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.2,
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
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── Scrollable Rides Section Only ───
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                      child: Text(
                        '${filteredTrips.length} ${filteredTrips.length == 1 ? 'Ride' : 'Rides'} Found',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),

                  if (tripsState.isLoading)
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: 100,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => const TripCardSkeleton(),
                          childCount: 3,
                        ),
                      ),
                    )
                  else if (filteredTrips.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.search_off_rounded,
                                size: 40,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'No rides found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Try adjusting your search criteria',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: 100,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _buildModernTripCard(context, filteredTrips[index]);
                        }, childCount: filteredTrips.length),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),

        // Dismiss layer when suggestions dropdown is active
        if (_fromFocusNode.hasFocus || _toFocusNode.hasFocus)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _fromFocusNode.unfocus();
                _toFocusNode.unfocus();
              },
            ),
          ),

        // Floating Suggestions Overlay for "From" field
        if (_fromFocusNode.hasFocus)
          CompositedTransformFollower(
            link: _fromLayerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 0),
            child: SizedBox(
              width: cardWidth,
              child: Material(
                color: Colors.transparent,
                child: _buildSuggestionsList(
                  query: _selectedFrom,
                  places: allPlaces,
                  onSelected: (val) {
                    setState(() {
                      _selectedFrom = val;
                      _fromController.text = val;
                      _fromFocusNode.unfocus();
                    });
                  },
                ),
              ),
            ),
          ),

        // Floating Suggestions Overlay for "To" field
        if (_toFocusNode.hasFocus)
          CompositedTransformFollower(
            link: _toLayerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 0),
            child: SizedBox(
              width: cardWidth,
              child: Material(
                color: Colors.transparent,
                child: _buildSuggestionsList(
                  query: _selectedTo,
                  places: allPlaces,
                  onSelected: (val) {
                    setState(() {
                      _selectedTo = val;
                      _toController.text = val;
                      _toFocusNode.unfocus();
                    });
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }


  Widget _buildSuggestionsList({
    required String query,
    required List<String> places,
    required ValueChanged<String> onSelected,
  }) {
    final filtered = places.where((p) {
      if (query.isEmpty || query.toLowerCase() == 'all') return true;
      return p.toLowerCase().contains(query.toLowerCase());
    }).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final place = filtered[index];
            return Material(
              color: Colors.white,
              child: InkWell(
                onTap: () => onSelected(place),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF1F5F9)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        place,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildModernTripCard(BuildContext context, Map<String, dynamic> trip) {
    final double rawPriceVal = double.tryParse(trip['price'].toString()) ?? 0.0;
    final String priceStr = rawPriceVal.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );

    // ── Parse seats ──
    final int totalSeats = trip['total_seats'] as int? ?? 40;
    final int bookedCount = (trip['booked_seats'] as List?)?.length ?? 0;
    final int seatsLeft = (totalSeats - bookedCount).clamp(0, totalSeats);

    // ── Parse distance ──
    final routeObj = trip['route'];
    final vehicleObj = trip['vehicle'];

    // ── Parse departure & arrival times & calculate real-time duration ──
    String depTime = '';
    String arrTime = '';
    DateTime? depDt;
    DateTime? arrDt;
    final String depRaw = trip['departure']?.toString() ?? '';
    final String arrRaw = trip['arrival']?.toString() ?? '';

    if (depRaw.isNotEmpty) {
      depDt = DateTime.tryParse(depRaw.replaceAll(' ', 'T'));
      if (depDt != null) {
        depTime = '${depDt.hour.toString().padLeft(2, '0')}:${depDt.minute.toString().padLeft(2, '0')}';
      } else {
        final parts = depRaw.split(' ');
        if (parts.length >= 2) depTime = parts[1];
      }
    }
    if (arrRaw.isNotEmpty) {
      arrDt = DateTime.tryParse(arrRaw.replaceAll(' ', 'T'));
      if (arrDt != null) {
        arrTime = '${arrDt.hour.toString().padLeft(2, '0')}:${arrDt.minute.toString().padLeft(2, '0')}';
      } else {
        final parts = arrRaw.split(' ');
        if (parts.length >= 2) arrTime = parts[1];
      }
    }

    // ── Calculate Real-Time Duration ──
    String durationLabel = '';
    final dynamic rawDuration = routeObj?['estimated_duration'] ?? trip['estimated_duration'];

    if (rawDuration != null && rawDuration.toString().isNotEmpty) {
      if (rawDuration is int || rawDuration is double) {
        final totalMin = (rawDuration as num) ~/ 60;
        final h = totalMin ~/ 60;
        final m = totalMin % 60;
        durationLabel = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
      } else {
        final str = rawDuration.toString();
        final parts = str.split(':');
        if (parts.length >= 2) {
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts[1]) ?? 0;
          durationLabel = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
        }
      }
    }

    // If duration not in route, dynamically calculate from departure and arrival timestamps!
    if (durationLabel.isEmpty && depDt != null && arrDt != null) {
      Duration diff = arrDt.difference(depDt);
      if (diff.isNegative) {
        // Arrival is on the next day (e.g., 23:00 to 05:00)
        diff += const Duration(days: 1);
      }
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      durationLabel = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
    } else if (durationLabel.isEmpty && depTime.contains(':') && arrTime.contains(':')) {
      // Calculate from HH:MM string representations
      try {
        final depParts = depTime.split(':');
        final arrParts = arrTime.split(':');
        final depMin = int.parse(depParts[0]) * 60 + int.parse(depParts[1]);
        var arrMin = int.parse(arrParts[0]) * 60 + int.parse(arrParts[1]);
        if (arrMin < depMin) arrMin += 24 * 60; // crossed midnight
        final diffMin = arrMin - depMin;
        final h = diffMin ~/ 60;
        final m = diffMin % 60;
        durationLabel = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
      } catch (_) {}
    }

    // ── Vehicle type label ──
    final String vehicleType = vehicleObj?['type']?.toString() ?? 'Bus';
    final String typeLabel = vehicleType[0].toUpperCase() + vehicleType.substring(1);

    // ── Amenities ──
    final List<dynamic> rawAmenities = (trip['amenities'] as List?) ?? [];
    final List<String> amenities = rawAmenities.map((e) => e.toString()).toList();
    if (amenities.isEmpty) {
      amenities.addAll(['AC', 'WiFi', 'Charging Ports', 'Reclining Seats', 'Luggage Space']);
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          SeatyPageRoute(
            page: BusDetailsScreen(trip: trip),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: Bus Name & Type | Price & per person ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip['bus_name'] ?? 'Express Lines',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                          letterSpacing: 0.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        typeLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rs. $priceStr',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB), // Brand Royal Blue like navbar
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'per person',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Row 2: Origin Time ──── Line & Duration ──── Dest Time ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Departure (Time + Origin City)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      depTime.isNotEmpty ? depTime : '07:00',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      trip['origin'] ?? 'Origin',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),

                // Center Timeline (Line with dots + Duration text below)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: const Color(0xFF93C5FD),
                              ),
                            ),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          durationLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Arrival (Time + Destination City)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      arrTime.isNotEmpty ? arrTime : '11:30',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      trip['destination'] ?? 'Destination',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 22),

            // ── Row 3: Minimal Amenities Inline Row & Bottom-Right Rating ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: amenities.map((ame) {
                      return _buildMinimalAmenityIcon(ame);
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB800), // Gold star
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      ((trip['rating'] ?? trip['average_rating']) as num?)?.toStringAsFixed(1) ?? '4.8',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimalAmenityIcon(String name) {
    final n = name.toLowerCase();
    IconData icon;

    if (n.contains('luggage') || n.contains('baggage') || n.contains('bag') || n.contains('suitcases') || n.contains('space')) {
      icon = Icons.luggage_outlined;
    } else if (n.contains('wifi') || n.contains('wi-fi')) {
      icon = Icons.wifi_rounded;
    } else if (n.contains('power') || n.contains('charg') || n.contains('plug') || n.contains('outlet')) {
      icon = Icons.power_outlined;
    } else if (n.contains('tv') || n.contains('screen') || n.contains('entertainment')) {
      icon = Icons.tv_rounded;
    } else if (n.contains('snack') || n.contains('food') || n.contains('meal')) {
      icon = Icons.local_dining_outlined;
    } else if (n.contains('reclin') || n.contains('seat')) {
      icon = Icons.airline_seat_recline_normal_rounded;
    } else if (n.contains('restroom') || n.contains('toilet') || n.contains('wc')) {
      icon = Icons.wc_rounded;
    } else if (n.contains('a/c') || n.contains('air') || n.contains('cool') || n.contains('snowflake') || n == 'ac' || n.startsWith('ac ') || n.endsWith(' ac') || n.contains(' ac ')) {
      icon = Icons.ac_unit_rounded;
    } else {
      icon = Icons.check_circle_outline_rounded;
    }

    return Tooltip(
      message: name,
      child: Icon(
        icon,
        size: 16,
        color: const Color(0xFF475569),
      ),
    );
  }

  Widget _buildSearchInputRow({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
    required VoidCallback onTap,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF64748B),
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onTap: onTap,
              onChanged: onChanged,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 8),
            suffix,
          ],
        ],
      ),
    );
  }

  Widget _buildDateQuickPill(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE4E6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF991B1B),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _formatDateOfJourney(DateTime? date) {
    if (date == null) return 'All Dates';
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return "${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}";
  }
}
