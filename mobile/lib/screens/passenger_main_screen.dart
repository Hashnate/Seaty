import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/screens/tracker_screen.dart';
import 'package:seaty/screens/ticket_screen.dart';
import 'package:seaty/screens/profile_screen.dart';
import 'package:seaty/screens/bus_details_screen.dart';

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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true, // Let content scroll behind the floating capsule
      extendBodyBehindAppBar: true,
      body: _tabs[_currentIndex],
      bottomNavigationBar: _buildTelegramBottomNavBar(context),
    );
  }

  Widget _buildTelegramBottomNavBar(BuildContext context) {
    return Container(
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
    }).toList();

    final double topPadding = MediaQuery.of(context).padding.top;
    final double heroHeight = 310.0 + topPadding;

    return Column(
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
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.notifications_outlined,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    SeatyPageRoute(
                                      page: const NotificationsScreen(),
                                    ),
                                  );
                                },
                              ),
                              if (notificationsState.unreadNotificationsCount > 0)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEF4444),
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 14,
                                      minHeight: 14,
                                    ),
                                    child: Text(
                                      '${notificationsState.unreadNotificationsCount}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
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
                                          _buildSearchInputRow(
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
                                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                          _buildSearchInputRow(
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
                                  if (_fromFocusNode.hasFocus)
                                    _buildSuggestionsList(
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
                                  if (_toFocusNode.hasFocus)
                                    _buildSuggestionsList(
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
                    '${filteredTrips.length} Rides Found',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),

              if (filteredTrips.isEmpty)
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
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final place = filtered[index];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => onSelected(place),
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
                      color: Color(0xFF64748B),
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
            );
          },
        ),
      ),
    );
  }



  Widget _getAmenityIcon(String name, {Color color = const Color(0xFF64748B)}) {
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

  Widget _buildModernTripCard(BuildContext context, Map<String, dynamic> trip) {
    final String priceStr =
        double.tryParse(trip['price'].toString())?.toStringAsFixed(0) ??
        trip['price'].toString();
    final int totalSeats = trip['total_seats'] as int? ?? 40;
    final int bookedCount = (trip['booked_seats'] as List?)?.length ?? 0;
    final int seatsLeft = (totalSeats - bookedCount).clamp(0, totalSeats);

    // Cycle through generated carousel images for cards
    final String busImage = (trip['id'].hashCode % 3 == 0)
        ? 'assets/images/bus_slider_1.png'
        : ((trip['id'].hashCode % 3 == 1)
            ? 'assets/images/bus_slider_2.png'
            : 'assets/images/bus_slider_3.png');

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
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0A2540).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Top Image Banner Header (Matching Reference Prompt) ──
            SizedBox(
              height: 140,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    busImage,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFF0F172A),
                      child: const Icon(Icons.directions_bus_rounded, color: Colors.white24, size: 48),
                    ),
                  ),
                  // Dark Gradient Overlay for contrast
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
                  // Overlay Badges: Reg Pill top-left, Rating Box top-right
                  Positioned(
                    top: 10,
                    left: 12,
                    right: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Reg Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24, width: 0.8),
                          ),
                          child: Text(
                            trip['reg'] ?? 'LUX-BUS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Green Rating Box (4.2 ★)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF047857), // Green rating box
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                '4.2',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                              SizedBox(width: 3),
                              Icon(
                                Icons.star_rounded,
                                color: Colors.white,
                                size: 12,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bottom Row inside Image Banner: Title & Price Pill
                  Positioned(
                    bottom: 10,
                    left: 12,
                    right: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            trip['bus_name'] ?? 'Soyaru Sampath Express',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black54, offset: Offset(0, 1)),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            'Rs. $priceStr',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 2. Card Content Body ──
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Route Line (Origin -> Destination)
                  Row(
                    children: [
                      Text(
                        trip['origin'] ?? '',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.east_rounded,
                        color: Color(0xFF2563EB),
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          trip['destination'] ?? '',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Distance & Location Subtitle (e.g., 8.1 km • Rajarajeshwari Nagar, Bangalore)
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 13,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '8.1 km • ${trip['origin'] ?? 'Location'}, ${trip['destination'] ?? 'City'}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Cuisines / Amenities & Status Pill Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Status Badge: "Open till 1AM ∨"
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Open till 1AM',
                              style: TextStyle(
                                color: Color(0xFF047857),
                                fontWeight: FontWeight.w800,
                                fontSize: 10.5,
                              ),
                            ),
                            SizedBox(width: 3),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFF047857),
                              size: 14,
                            ),
                          ],
                        ),
                      ),

                      // Departure Time Tag & Amenities Icons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (trip['amenities'] != null && (trip['amenities'] as List).isNotEmpty) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: (trip['amenities'] as List).take(3).map<Widget>((ame) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 4.0),
                                  child: _getAmenityIcon(ame.toString()),
                                );
                              }).toList(),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 12,
                                  color: Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  trip['departure'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E40AF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── 3. Bottom Action Row ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(
                  top: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Seat Availability Pill
                  Builder(
                    builder: (context) {
                      final isLowSeats = seatsLeft <= 10;
                      final Color seatsColor = isLowSeats ? const Color(0xFFEF4444) : const Color(0xFF10B981);
                      final Color seatsBgColor = seatsColor.withValues(alpha: 0.1);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: seatsBgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.event_seat_rounded,
                              size: 12,
                              color: seatsColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$seatsLeft seats left',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: seatsColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Dark Book Seats Button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Book Seats',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 13,
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
