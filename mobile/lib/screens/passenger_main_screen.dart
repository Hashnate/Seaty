import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/theme/app_colors.dart';
import 'package:seaty/providers/banners_provider.dart';
import 'package:seaty/screens/tracker_screen.dart';
import 'package:seaty/screens/ticket_screen.dart';
import 'package:seaty/screens/profile_screen.dart';
import 'package:seaty/screens/bus_details_screen.dart';
import 'package:seaty/screens/notifications_screen.dart';
import 'package:seaty/widgets/shimmer_loading.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:seaty/providers/notifications_provider.dart';

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
    final notificationsState = ref.watch(notificationsProvider);
    final unreadCount = notificationsState.unreadNotificationsCount;

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
            badgeCount: unreadCount,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData outlineIcon,
    IconData solidIcon,
    String label, {
    int badgeCount = 0,
  }) {
    final isSelected = _currentIndex == index;
    final activeColor = Colors.white;
    final activeBgColor = const Color(0xFF2563EB); // Matte Orange
    final inactiveColor = Colors.white.withOpacity(0.75);

    Widget iconWidget = Icon(
      isSelected ? solidIcon : outlineIcon,
      color: isSelected ? activeColor : inactiveColor,
      size: 24,
    );

    if (badgeCount > 0) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444), // Vibrant Red
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF0F172A),
                  width: 1.5,
                ),
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

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
              iconWidget,
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
  bool _isHeroVisible = true;

  /// How far ahead a journey date can be picked.
  ///
  /// Must stay in step with the backend: `list_trips` only materialises trips
  /// from `trip_schedules` for dates within `today + 5 days`, so any date past
  /// that is guaranteed to come back empty. Offering them made the search look
  /// broken. Widening this alone changes nothing - the backend window has to
  /// move with it.
  static const int _bookingHorizonDays = 5;

  /// Shipped with the app. Used only when the admin console has no active
  /// banner configured, or the banners request fails - so the carousel is
  /// never empty and never divides by zero.
  static const List<String> _bundledHeroImages = [
    'assets/images/bus_slider_1.png',
    'assets/images/bus_slider_2.png',
    'assets/images/bus_slider_3.png',
  ];

  /// Remote banners are only adopted once every one of them is decoded and in
  /// the image cache. Swapping the moment the URLs arrived meant the carousel
  /// tore down the bundled asset and put up `Image.network`, which then showed
  /// its placeholder for as long as the download took - the image -> grey ->
  /// dark -> image flicker on a cold start.
  List<String> _remoteHeroUrls = const [];
  bool _remoteHeroReady = false;

  /// Admin-managed banners when available, otherwise the bundled assets.
  List<String> get _heroImages =>
      _remoteHeroReady && _remoteHeroUrls.isNotEmpty
          ? _remoteHeroUrls
          : _bundledHeroImages;

  /// Downloads and decodes every banner, and only then swaps the carousel over,
  /// so the change is a single clean cut with no loading state on screen.
  Future<void> _adoptRemoteHeroBanners(List<String> urls) async {
    if (urls.isEmpty) return;
    if (urls.join('|') == _remoteHeroUrls.join('|') && _remoteHeroReady) return;

    for (final url in urls) {
      if (!mounted) return;
      try {
        await precacheImage(NetworkImage(url), context);
      } catch (_) {
        // A single unreachable banner shouldn't strand the carousel on the
        // bundled assets forever - keep going and adopt whatever decoded.
      }
    }

    if (!mounted) return;
    setState(() {
      _remoteHeroUrls = urls;
      _remoteHeroReady = true;
      if (_heroImageIndex >= urls.length) _heroImageIndex = 0;
    });
  }

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
    // ref.listen only fires on *change*, so banners already fetched before this
    // tab mounted (e.g. returning to Home) would never be adopted. Pick up any
    // existing value once the first frame has a context to precache against.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final existing = ref.read(bannersProvider).imageUrls;
      if (existing.isNotEmpty) _adoptRemoteHeroBanners(existing);
    });
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
    if (_fromFocusNode.hasFocus || _toFocusNode.hasFocus) {
      if (!_isHeroVisible) {
        setState(() => _isHeroVisible = true);
      }
    }
    setState(() {});
  }

  void _onScroll() {
    if (_scrollController.hasClients && _scrollController.offset <= 10 && !_isHeroVisible) {
      setState(() {
        _isHeroVisible = true;
      });
    }
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
    // Listened to (not watched): adopting the banners is deferred until they
    // are precached, so a plain rebuild here would only cause the flicker.
    ref.listen<BannersState>(bannersProvider, (previous, next) {
      if (next.imageUrls.isNotEmpty) {
        _adoptRemoteHeroBanners(next.imageUrls);
      }
    });

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

        // Both are favourites or both are not favourites -> Sort by early departure first
        DateTime? parseTripDeparture(dynamic dep) {
          if (dep == null) return null;
          final str = dep.toString().trim();
          if (str.isEmpty) return null;
          final dt = DateTime.tryParse(str.replaceAll(' ', 'T'));
          if (dt != null) return dt;
          return null;
        }

        final DateTime? aDep = parseTripDeparture(a['departure']);
        final DateTime? bDep = parseTripDeparture(b['departure']);

        if (aDep != null && bDep != null) {
          final cmp = aDep.compareTo(bDep);
          if (cmp != 0) return cmp;
        } else if (aDep != null && bDep == null) {
          return -1;
        } else if (aDep == null && bDep != null) {
          return 1;
        }

        final String aDepStr = a['departure']?.toString() ?? '';
        final String bDepStr = b['departure']?.toString() ?? '';
        return aDepStr.compareTo(bDepStr);
      });

    final double topPadding = MediaQuery.of(context).padding.top;
    final double heroHeight = 275.0 + topPadding;

    // The welcome text + search card are bottom-anchored inside the fixed-height
    // hero, so anything added to that block grows *upwards*. The "Clear all
    // filters" chip therefore used to shove the welcome line up under the Seaty
    // app bar - it now shares a row with that line instead of taking its own.
    final bool hasActiveFilters =
        _selectedFrom.isNotEmpty || _selectedTo.isNotEmpty || _selectedDate != null;

    final double cardWidth = MediaQuery.of(context).size.width - 40;

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.direction == ScrollDirection.reverse) {
          // User scrolling down: hide hero for full view of trips
          if (_isHeroVisible && _scrollController.hasClients && _scrollController.offset > 20) {
            setState(() => _isHeroVisible = false);
          }
        } else if (notification.direction == ScrollDirection.forward) {
          // User scrolling up: show hero again
          if (!_isHeroVisible) {
            setState(() => _isHeroVisible = true);
          }
        }
        return false;
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              // ─── Collapsible Auto-Sliding Hero Header ───
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                height: _isHeroVisible ? heroHeight : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isHeroVisible ? 1.0 : 0.0,
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      height: heroHeight,
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(28),
                          bottomRight: Radius.circular(28),
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
                                final source = _heroImages[index];
                                final isRemote = source.startsWith('http');
                                // A broken/unreachable admin banner must not leave a
                                // blank hero, so both paths fall back to the branded
                                // placeholder below.
                                Widget placeholder() => Container(
                                      color: const Color(0xFF0F172A),
                                      child: const Center(
                                        child: Icon(
                                          Icons.directions_bus_rounded,
                                          color: Colors.white24,
                                          size: 64,
                                        ),
                                      ),
                                    );

                                if (isRemote) {
                                  // Banners are precached before adoption, so this
                                  // normally paints immediately. If the cache was
                                  // evicted, show the bundled artwork rather than a
                                  // dark box - that dark frame was the visible flicker.
                                  Widget bundledStandIn() => Image.asset(
                                        _bundledHeroImages[index % _bundledHeroImages.length],
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorBuilder: (context, error, stackTrace) => placeholder(),
                                      );
                                  return Image.network(
                                    source,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    // Hold the branded backdrop while bytes arrive
                                    // rather than flashing white.
                                    loadingBuilder: (context, child, progress) =>
                                        progress == null ? child : bundledStandIn(),
                                    errorBuilder: (context, error, stackTrace) => bundledStandIn(),
                                  );
                                }

                                return Image.asset(
                                  source,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) => placeholder(),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Image.asset(
                                            'assets/images/app_icon.png',
                                            width: 26,
                                            height: 26,
                                            color: Colors.white,
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, error, stackTrace) => Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2563EB),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.directions_bus_rounded,
                                                color: Colors.white,
                                                size: 15,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Seaty',
                                            style: TextStyle(
                                              fontSize: 19,
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

                            // 3. Welcome text + Search Card
                            SafeArea(
                              bottom: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // Welcome line and the clear-filters chip
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Where are you traveling today?',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              letterSpacing: -0.4,
                                              shadows: [
                                                Shadow(blurRadius: 6, color: Colors.black54, offset: Offset(0, 1)),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (hasActiveFilters) ...[
                                          const SizedBox(width: 8),
                                          TextButton(
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
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                                                fontSize: 10.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 6),

                                    // Main Search Input Card ("from to card") - Anchored at bottom of image
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Glassmorphic / Clean White Search Card
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.96),
                                            borderRadius: BorderRadius.circular(18),
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
                                                    top: 20,
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
                                                        padding: const EdgeInsets.all(6),
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
                                                          size: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const Divider(height: 1, color: Color(0xFFE2E8F0)),

                                              // Date Row
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.calendar_month_outlined,
                                                      color: Color(0xFF64748B),
                                                      size: 18,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: GestureDetector(
                                                        behavior: HitTestBehavior.opaque,
                                                        onTap: () async {
                                                          final now = DateTime.now();
                                                          final today = DateTime(now.year, now.month, now.day);
                                                          final lastSelectable = today.add(
                                                            const Duration(days: _bookingHorizonDays),
                                                          );
                                                          // showDatePicker asserts if initialDate falls
                                                          // outside the range, so clamp a previously
                                                          // chosen (possibly stale) date into it.
                                                          final desired = _selectedDate ?? today;
                                                          final initial = desired.isBefore(today)
                                                              ? today
                                                              : (desired.isAfter(lastSelectable)
                                                                  ? lastSelectable
                                                                  : desired);

                                                          final DateTime? picked = await showDatePicker(
                                                            context: context,
                                                            initialDate: initial,
                                                            firstDate: today,
                                                            lastDate: lastSelectable,
                                                            helpText: 'Select journey date',
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
                                                                fontSize: 9.5,
                                                                fontWeight: FontWeight.w600,
                                                                color: Color(0xFF64748B),
                                                              ),
                                                            ),
                                                            const SizedBox(height: 1),
                                                            Text(
                                                              _formatDateOfJourney(_selectedDate),
                                                              style: const TextStyle(
                                                                color: Color(0xFF0F172A),
                                                                fontSize: 12.5,
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
                                                        const SizedBox(width: 5),
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
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 42,
                                          child: ElevatedButton(
                                            onPressed: () {
                                              _fromFocusNode.unfocus();
                                              _toFocusNode.unfocus();
                                              final dateStr = _selectedDate != null
                                                  ? "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}"
                                                  : null;
                                              ref.read(tripsProvider.notifier).loadTrips(date: dateStr);
                                              SeatyNotifications.show(
                                                context,
                                                'Searching buses from $_selectedFrom to $_selectedTo...',
                                                isInfo: true,
                                                duration: const Duration(seconds: 1),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFEF4444),
                                              foregroundColor: Colors.white,
                                              elevation: 4,
                                              shadowColor: Colors.black45,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(22),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.search_rounded, size: 17),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Search buses',
                                                  style: TextStyle(
                                                    fontSize: 14,
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
      ),
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

    if (durationLabel.isEmpty && depDt != null && arrDt != null) {
      Duration diff = arrDt.difference(depDt);
      if (diff.isNegative) {
        diff += const Duration(days: 1);
      }
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      durationLabel = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
    } else if (durationLabel.isEmpty && depTime.contains(':') && arrTime.contains(':')) {
      try {
        final depParts = depTime.split(':');
        final arrParts = arrTime.split(':');
        final depMin = int.parse(depParts[0]) * 60 + int.parse(depParts[1]);
        var arrMin = int.parse(arrParts[0]) * 60 + int.parse(arrParts[1]);
        if (arrMin < depMin) arrMin += 24 * 60;
        final diffMin = arrMin - depMin;
        final h = diffMin ~/ 60;
        final m = diffMin % 60;
        durationLabel = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
      } catch (_) {}
    }

    // ── Category & seating info ──
    String categoryLabel = (trip['bus_type'] ?? trip['category'] ?? vehicleObj?['type'] ?? '').toString().toUpperCase();
    if (categoryLabel.isEmpty || categoryLabel == 'BUS') {
      final bool isAc = (trip['is_ac'] == true) || (vehicleObj?['is_ac'] == true);
      categoryLabel = isAc ? 'A/C SLEEPER' : 'EXPRESS';
    }

    // ── Dynamic Available Seats calculation ──
    final int totalSeats = (trip['total_seats'] ?? vehicleObj?['total_seats']) as int? ?? 40;
    int bookedCount = 0;
    final dynamic bookedRaw = trip['booked_seats'] ?? vehicleObj?['booked_seats'];
    if (bookedRaw is List) {
      bookedCount = bookedRaw.length;
    } else if (trip['booked_seats_count'] is int) {
      bookedCount = trip['booked_seats_count'];
    }
    final int seatsLeft = (trip['available_seats'] as int?) ??
        (trip['seats_available'] as int?) ??
        (totalSeats - bookedCount).clamp(0, totalSeats);

    // ── Rating badge ──
    final dynamic val = trip['rating'] ?? trip['average_rating'] ?? vehicleObj?['average_rating'] ?? vehicleObj?['rating'];
    final num? r = (val is num) ? val : num.tryParse(val?.toString() ?? '');

    Widget ratingWidget;
    if (r == null || r <= 0) {
      ratingWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'New',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      );
    } else {
      ratingWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star_rounded,
              color: Color(0xFFF59E0B),
              size: 15,
            ),
            const SizedBox(width: 3),
            Text(
              r.toDouble().toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            ),
          ],
        ),
      );
    }

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
        margin: const EdgeInsets.only(bottom: 16),
        child: CustomPaint(
          painter: _TicketCardBorderPainter(
            cornerRadius: 16.0,
            notchRadius: 10.0,
            notchYFromBottom: 58.0,
          ),
          child: ClipPath(
            clipper: _TicketCardClipper(
              cornerRadius: 16.0,
              notchRadius: 10.0,
              notchYFromBottom: 58.0,
            ),
            child: Container(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Upper Ticket Stub Section ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row: Operator Name + Rating Pill
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                trip['bus_name'] ?? 'Soyaru Sampath Superline',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ratingWidget,
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Time & Route Timeline Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Departure (23:00 / Trincomalee)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  depTime.isNotEmpty ? depTime : '23:00',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  trip['origin'] ?? 'Trincomalee',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                            // Route Timeline Center Graphics
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 26),
                                child: Column(
                                  children: [
                                    Text(
                                      '${durationLabel.isNotEmpty ? durationLabel : '6h'} • DIRECT',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF94A3B8),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        // Left Origin Node (Concentric halo dot)
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFDBEAFE),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Container(
                                              width: 5,
                                              height: 5,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF2563EB),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Left Solid Gradient Line Bar
                                        Expanded(
                                          child: Container(
                                            height: 2.5,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(2),
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Center Bus Badge (Dark gradient with blue accent ring)
                                        Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.directions_bus_rounded,
                                            color: Colors.white,
                                            size: 15,
                                          ),
                                        ),
                                        // Right Solid Gradient Line Bar
                                        Expanded(
                                          child: Container(
                                            height: 2.5,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(2),
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Right Destination Node (Hollow ring dot)
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: const Color(0xFF0F172A),
                                              width: 2.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '$seatsLeft seats left',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: seatsLeft <= 5 ? const Color(0xFFE11D48) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Arrival (05:00 / Colombo)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  arrTime.isNotEmpty ? arrTime : '05:00',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  trip['destination'] ?? 'Colombo',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),
                      ],
                    ),
                  ),

                  // ── Horizontal Dashed Divider Line ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CustomPaint(
                      size: const Size(double.infinity, 1),
                      painter: _DashedLinePainter(
                        color: const Color(0xFFCBD5E1),
                        dashWidth: 5,
                        dashSpace: 4,
                      ),
                    ),
                  ),

                  // ── Bottom Ticket Stub Section (Amenities + Price + Action Button) ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Amenities Row
                        Expanded(
                          child: Wrap(
                            spacing: 14,
                            runSpacing: 6,
                            children: amenities.take(4).map((ame) {
                              return _buildMinimalAmenityIcon(ame);
                            }).toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Price & Book Arrow Action
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'FROM',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF94A3B8),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  'Rs. $priceStr',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF64748B),
            size: 20,
          ),
          const SizedBox(width: 12),
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

class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  _DashedLinePainter({
    this.color = const Color(0xFFCBD5E1),
    double? strokeWidth,
    this.dashWidth = 5.0,
    this.dashSpace = 4.0,
  }) : strokeWidth = strokeWidth ?? 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    double startX = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashSpace != dashSpace;
}

Path _getTicketPath(Size size, double cornerRadius, double notchRadius, double notchYFromBottom) {
  final path = Path();
  final double notchY = (size.height - notchYFromBottom).clamp(0.0, size.height);

  // Start top left after corner
  path.moveTo(cornerRadius, 0);

  // Top edge
  path.lineTo(size.width - cornerRadius, 0);

  // Top right corner
  path.arcToPoint(Offset(size.width, cornerRadius), radius: Radius.circular(cornerRadius));

  // Right edge down to notch top
  if (notchY - notchRadius > cornerRadius) {
    path.lineTo(size.width, notchY - notchRadius);
    // Right notch (inward arc)
    path.arcToPoint(
      Offset(size.width, notchY + notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
  }

  // Right edge down to bottom right corner
  path.lineTo(size.width, size.height - cornerRadius);

  // Bottom right corner
  path.arcToPoint(Offset(size.width - cornerRadius, size.height), radius: Radius.circular(cornerRadius));

  // Bottom edge
  path.lineTo(cornerRadius, size.height);

  // Bottom left corner
  path.arcToPoint(Offset(0, size.height - cornerRadius), radius: Radius.circular(cornerRadius));

  // Left edge up to notch bottom
  if (notchY + notchRadius < size.height - cornerRadius) {
    path.lineTo(0, notchY + notchRadius);
    // Left notch (inward arc)
    path.arcToPoint(
      Offset(0, notchY - notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
  }

  // Left edge up to top left corner
  path.lineTo(0, cornerRadius);

  // Top left corner
  path.arcToPoint(Offset(cornerRadius, 0), radius: Radius.circular(cornerRadius));

  path.close();
  return path;
}

class _TicketCardClipper extends CustomClipper<Path> {
  final double cornerRadius;
  final double notchRadius;
  final double notchYFromBottom;

  _TicketCardClipper({
    this.cornerRadius = 16.0,
    this.notchRadius = 10.0,
    required this.notchYFromBottom,
  });

  @override
  Path getClip(Size size) {
    return _getTicketPath(size, cornerRadius, notchRadius, notchYFromBottom);
  }

  @override
  bool shouldReclip(covariant _TicketCardClipper oldClipper) {
    return oldClipper.cornerRadius != cornerRadius ||
        oldClipper.notchRadius != notchRadius ||
        oldClipper.notchYFromBottom != notchYFromBottom;
  }
}

class _TicketCardBorderPainter extends CustomPainter {
  final double cornerRadius;
  final double notchRadius;
  final double notchYFromBottom;

  _TicketCardBorderPainter({
    this.cornerRadius = 16.0,
    this.notchRadius = 10.0,
    required this.notchYFromBottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _getTicketPath(size, cornerRadius, notchRadius, notchYFromBottom);

    // 1. Draw Drop Shadow along the ticket clipped path
    canvas.drawShadow(
      path,
      const Color(0xFF0F172A).withValues(alpha: 0.12),
      6.0,
      true,
    );

    // 2. Draw Outline Border
    final borderPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _TicketCardBorderPainter oldDelegate) =>
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.notchRadius != notchRadius ||
      oldDelegate.notchYFromBottom != notchYFromBottom;
}
