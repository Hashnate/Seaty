import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/theme/app_theme.dart';

class BusDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> trip;

  const BusDetailsScreen({super.key, required this.trip});

  @override
  ConsumerState<BusDetailsScreen> createState() => _BusDetailsScreenState();
}

class _BusDetailsScreenState extends ConsumerState<BusDetailsScreen> {
  bool _isLoadingReviews = true;
  double _avgRating = 0.0;
  int _totalReviews = 0;
  List<dynamic> _reviewsList = [];

  late final PageController _pageController;
  Timer? _sliderTimer;
  int _currentImageIndex = 0;
  bool _isFavorite = false;

  final List<String> _sliderImages = [
    'assets/images/bus_slider_1.png',
    'assets/images/bus_slider_2.png',
    'assets/images/bus_slider_3.png',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startImageAutoSlider();
    _loadRealtimeReviews();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tripId = widget.trip['id']?.toString() ?? '';
      if (tripId.isNotEmpty) {
        ref.read(bookingsProvider.notifier).loadSeatAvailability(tripId, clearFirst: true);
      }
    });
  }

  void _startImageAutoSlider() {
    _sliderTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      if (_pageController.hasClients) {
        final nextPage = (_currentImageIndex + 1) % _sliderImages.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _sliderTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadRealtimeReviews() async {
    final vehicleId = widget.trip['vehicle_id']?.toString() ?? '';
    if (vehicleId.isEmpty) {
      if (mounted) setState(() => _isLoadingReviews = false);
      return;
    }

    final fleetNotifier = ref.read(fleetProvider.notifier);
    final data = await fleetNotifier.fetchVehicleReviews(vehicleId);

    if (mounted) {
      setState(() {
        _avgRating = (data['average_rating'] as num?)?.toDouble() ?? 0.0;
        _totalReviews = (data['total_reviews'] as num?)?.toInt() ?? 0;
        _reviewsList = (data['reviews'] as List?) ?? [];
        _isLoadingReviews = false;
      });
    }
  }

  void _showWriteReviewModal() {
    int selectedRating = 5;
    final commentCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Write a Review',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0A2540),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share your journey experience on ${widget.trip['bus_name'] ?? 'this bus'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Star Selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starVal = index + 1;
                      return IconButton(
                        icon: Icon(
                          starVal <= selectedRating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: const Color(0xFF2563EB),
                          size: 32,
                        ),
                        onPressed: () {
                          setModalState(() => selectedRating = starVal);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  // Comment TextField
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Describe your ride (comfort, cleanliness, punctuality)...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF0A2540)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final commentText = commentCtrl.text.trim();
                        final vehicleId = widget.trip['vehicle_id']?.toString() ?? '';
                        Navigator.pop(context);

                        if (vehicleId.isEmpty) return;

                        SeatyNotifications.show(
                          context,
                          'Submitting review...',
                          duration: const Duration(milliseconds: 800),
                        );

                        final success = await ref
                            .read(fleetProvider.notifier)
                            .submitVehicleReview(vehicleId, selectedRating, commentText);

                        if (success) {
                          await _loadRealtimeReviews();
                          if (mounted) {
                            SeatyNotifications.show(
                              context,
                              'Thank you! Your review is now live.',
                            );
                          }
                        } else {
                          if (mounted) {
                            SeatyNotifications.show(
                              context,
                              'Failed to submit review.',
                              isError: true,
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Submit Review',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _getAmenityIcon(String name, {Color color = const Color(0xFF2563EB)}) {
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
  Widget build(BuildContext context) {
    final bookingsState = ref.watch(bookingsProvider);
    final String priceStr =
        double.tryParse(widget.trip['price'].toString())?.toStringAsFixed(2) ??
        widget.trip['price'].toString();
    final int totalSeats = widget.trip['total_seats'] as int? ?? 40;
    final List<dynamic> tripBookedSeats = (widget.trip['booked_seats'] as List?) ?? [];
    final int bookedCount = bookingsState.bookedSeats.isNotEmpty 
        ? bookingsState.bookedSeats.length 
        : tripBookedSeats.length;
    final int seatsLeft = (totalSeats - bookedCount).clamp(0, totalSeats);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Scrollable Body Content with Header Slider & Overlapping Floating Card ──
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Image Slider Header with Overlapping Floating Card ──
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1. Auto-sliding Image Carousel (3s interval)
                      SizedBox(
                        height: 275,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            PageView.builder(
                              controller: _pageController,
                              itemCount: _sliderImages.length,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentImageIndex = index;
                                });
                              },
                              itemBuilder: (context, index) {
                                return Image.asset(
                                  _sliderImages[index],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: const Color(0xFF0F172A),
                                      child: const Center(
                                        child: Icon(
                                          Icons.directions_bus_rounded,
                                          size: 64,
                                          color: Colors.white24,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),

                            // Dark Gradient Overlay for optimal contrast
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.black.withValues(alpha: 0.55),
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.4),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),

                            // Top Action Bar (Back, Favorite, Share)
                            SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Circular Back Button
                                    GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.9),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.15),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.arrow_back_rounded,
                                          color: Color(0xFF0F172A),
                                          size: 20,
                                        ),
                                      ),
                                    ),

                                    // Favorite & Share Buttons
                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _isFavorite = !_isFavorite;
                                            });
                                            SeatyNotifications.show(
                                              context,
                                              _isFavorite ? 'Saved to favorites' : 'Removed from favorites',
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.9),
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.15),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                              color: _isFavorite ? Colors.redAccent : const Color(0xFF0F172A),
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        GestureDetector(
                                          onTap: () {
                                            SeatyNotifications.show(context, 'Share link copied to clipboard');
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.9),
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.15),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.ios_share_rounded,
                                              color: Color(0xFF0F172A),
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Image Count Indicator Badge (e.g. 1/3) at bottom right of image area
                            Positioned(
                              right: 16,
                              bottom: 85,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.photo_library_rounded,
                                      color: Colors.white,
                                      size: 13,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_currentImageIndex + 1}/${_sliderImages.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2. Overlapping Floating White Detail Card matching user screenshot
                      Container(
                        margin: const EdgeInsets.only(top: 210, left: 16, right: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header Row: Title & Rating Box
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.trip['bus_name'] ?? 'Torye - Drink Dine & Dance',
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF0F172A),
                                          letterSpacing: -0.4,
                                          height: 1.25,
                                        ),
                                      ),
                                      if (widget.trip['reg'] != null && widget.trip['reg'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            widget.trip['reg'].toString(),
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              color: Color(0xFF2563EB),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Rating Box with green background + Google badge
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF047857), // Green rating box
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _avgRating > 0 ? _avgRating.toStringAsFixed(1) : '4.2',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          const Icon(
                                            Icons.star_rounded,
                                            color: Colors.white,
                                            size: 13,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'G ',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF4285F4),
                                          ),
                                        ),
                                        Text(
                                          'Google',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      '${_totalReviews > 0 ? _totalReviews : "2K"} ratings',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Subtitle Row: Distance & Location
                            Row(
                              children: [
                                const Icon(
                                  Icons.place_rounded,
                                  size: 14,
                                  color: Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '8.1 km • ${widget.trip['origin'] ?? 'Rajarajeshwari Nagar'}, ${widget.trip['destination'] ?? 'Bangalore'}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Info Row: Cuisine / Bus type & price line
                            Text(
                              '${widget.trip['bus_type'] ?? 'Continental, North Indian'} | ₹$priceStr for two',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Bottom Row: Status Badge & Action Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Green Status Badge: "Open till 1AM ∨"
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(8),
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
                                          fontSize: 11.5,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Color(0xFF047857),
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),

                                // Directions & Call Action Icon Buttons
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        SeatyNotifications.show(context, 'Opening map directions...');
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: const Icon(
                                          Icons.alt_route_rounded,
                                          color: Color(0xFF0F172A),
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        SeatyNotifications.show(context, 'Calling venue support...');
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: const Icon(
                                          Icons.phone_rounded,
                                          color: Color(0xFF0F172A),
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Padding between floating card and remaining content
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Journey Details Card
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
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
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.circle_outlined,
                                color: Color(0xFF2563EB),
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.trip['origin'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0A2540),
                                      ),
                                    ),
                                    Text(
                                      'Departure: ${widget.trip['departure']}',
                                      style: const TextStyle(
                                        fontSize: 12,
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
                            padding: const EdgeInsets.only(left: 7.0, top: 2, bottom: 2),
                            child: Container(
                              width: 2,
                              height: 12,
                              color: const Color(0xFFCBD5E1),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFF0A2540),
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.trip['destination'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0A2540),
                                      ),
                                    ),
                                    Text(
                                      () {
                                        final departureStr = widget.trip['departure']?.toString() ?? '';
                                        final arrivalStr = widget.trip['arrival']?.toString() ?? '';
                                        if (departureStr.isNotEmpty && arrivalStr.isNotEmpty) {
                                          try {
                                            final dep = DateTime.parse(departureStr.replaceAll(' ', 'T'));
                                            final arr = DateTime.parse(arrivalStr.replaceAll(' ', 'T'));
                                            final diff = arr.difference(dep);
                                            final hours = diff.inHours;
                                            final mins = diff.inMinutes % 60;
                                            if (hours > 0) {
                                              return 'Arrival: Estimated $hours ${hours == 1 ? "hr" : "hrs"}${mins > 0 ? " $mins min" : ""} duration';
                                            } else if (mins > 0) {
                                              return 'Arrival: Estimated $mins min duration';
                                            }
                                          } catch (e) {
                                            debugPrint('Error parsing duration: $e');
                                          }
                                        }
                                        return 'Arrival: Estimated duration';
                                      }(),
                                      style: const TextStyle(
                                        fontSize: 12,
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
                    const SizedBox(height: 16),

                    // Seat Availability Stats
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A2540).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF0A2540).withValues(alpha: 0.1),
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
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$seatsLeft of $totalSeats Seats Available',
                                style: const TextStyle(
                                  color: Color(0xFF0A2540),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox.shrink(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Amenities Grid
                    if (widget.trip['amenities'] != null &&
                        (widget.trip['amenities'] as List).isNotEmpty) ...[
                      const Text(
                        'Bus Amenities & Services',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0A2540),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 2.7,
                            ),
                        itemCount: (widget.trip['amenities'] as List).length,
                        itemBuilder: (context, index) {
                          final name = widget.trip['amenities'][index].toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                _getAmenityIcon(name),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
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
                      const SizedBox(height: 24),
                    ],

                    // ── Dynamic Real-Time Passenger Reviews ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Passenger Reviews',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0A2540),
                            letterSpacing: -0.3,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFF2563EB),
                                    size: 15,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${_avgRating > 0 ? _avgRating.toStringAsFixed(1) : "N/A"} ($_totalReviews)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _showWriteReviewModal,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A2540),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.rate_review_rounded,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Review',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
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
                    const SizedBox(height: 12),

                    if (_isLoadingReviews)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF2563EB),
                            strokeWidth: 2.5,
                          ),
                        ),
                      )
                    else if (_reviewsList.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.star_outline_rounded,
                              size: 32,
                              color: Color(0xFF94A3B8),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'No reviews yet for this bus.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Be the first passenger to leave a review!',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: _reviewsList.map((item) {
                          final name = (item['passenger_name'] ?? 'Passenger').toString();
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'P';
                          final rating = (item['rating'] as num?)?.toInt() ?? 5;
                          final comment = (item['comment'] ?? '').toString();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
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
                                          radius: 14,
                                          backgroundColor: const Color(
                                            0xFF2563EB,
                                          ).withValues(alpha: 0.15),
                                          child: Text(
                                            initial,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2563EB),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0A2540),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Text(
                                      'Verified Passenger',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: List.generate(5, (starIdx) {
                                    return Icon(
                                      Icons.star_rounded,
                                      color: starIdx < rating
                                          ? const Color(0xFF2563EB)
                                          : const Color(0xFFCBD5E1),
                                      size: 14,
                                    );
                                  }),
                                ),
                                if (comment.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    comment,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF334155),
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

          // ── Bottom Action Bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
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
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'Rs. $priceStr',
                          style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Text(
                          '/ seat',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
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
                      SeatyPageRoute(
                        page: SeatSelectorScreen(trip: widget.trip),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A2540),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
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
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 15),
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
