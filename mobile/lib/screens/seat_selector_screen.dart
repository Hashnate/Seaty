import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/screens/booking_overview_screen.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:seaty/widgets/animated_3d_seat.dart';
import 'package:seaty/widgets/seaty_bus_loading.dart';

// Seat Selector Screen
class SeatSelectorScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> trip;
  const SeatSelectorScreen({super.key, required this.trip});

  @override
  ConsumerState<SeatSelectorScreen> createState() => _SeatSelectorScreenState();
}

class _SeatSelectorScreenState extends ConsumerState<SeatSelectorScreen> {
  bool _isLoading = true;

  dynamic _wsChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSeats();
      _initRealtimeWebSocket();
      _startSyncTimer();
    });
  }

  Future<void> _initRealtimeWebSocket() async {
    try {
      final tripId = widget.trip['id'].toString();
      final bookingsNotifier = ref.read(bookingsProvider.notifier);
      final wsUri = 'ws://127.0.0.1:8000/api/v1/trips/ws/$tripId';

      _wsChannel = await WebSocket.connect(wsUri);
      _wsChannel?.listen(
        (message) {
          try {
            final data = json.decode(message.toString());
            final event = data['event'];
            final List seats = data['seats'] ?? [];

            if (event == 'SEAT_HELD') {
              bookingsNotifier.addHeldSeats(seats.map((s) => s.toString()).toList());
            } else if (event == 'SEAT_BOOKED') {
              bookingsNotifier.addBookedSeats(seats.map((s) => s.toString()).toList());
            } else if (event == 'SEAT_RELEASED') {
              bookingsNotifier.releaseSeats(seats.map((s) => s.toString()).toList());
            }
          } catch (e) {
            debugPrint('Error parsing WS message: $e');
          }
        },
        onError: (err) => debugPrint('WebSocket error: $err'),
        onDone: () => debugPrint('WebSocket connection closed.'),
      );
    } catch (e) {
      debugPrint('Real-time WebSocket connection failed: $e');
    }
  }

  void _startSyncTimer() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (mounted) {
        final bookingsNotifier = ref.read(bookingsProvider.notifier);
        await bookingsNotifier.loadSeatAvailability(widget.trip['id'].toString());
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    try {
      _wsChannel?.close();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _refreshSeats() async {
    setState(() => _isLoading = true);
    final bookingsNotifier = ref.read(bookingsProvider.notifier);
    bookingsNotifier.clearSelectedSeats();
    await bookingsNotifier.loadSeatAvailability(widget.trip['id'].toString(), clearFirst: true);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showPassengerDetailsSheet(
    BuildContext context,
    AuthState auth,
    BookingsState bookingsState,
  ) {
    final selectedSeats = bookingsState.selectedSeats.toList();
    if (selectedSeats.isEmpty) return;

    String bookingFor = 'self'; // 'self' or 'other'

    final nameController = TextEditingController(text: auth.userName);
    final phoneController = TextEditingController(text: auth.userPhone);
    final nicController = TextEditingController(text: auth.userNic);
    String primaryGender =
        bookingsState.selectedSeatGenders[selectedSeats.first] ??
        (auth.userGender.isEmpty ? 'Male' : auth.userGender);

    final Map<String, String> guestGenders = {};
    for (int i = 1; i < selectedSeats.length; i++) {
      final String seat = selectedSeats[i];
      guestGenders[seat] = bookingsState.selectedSeatGenders[seat] ?? 'Female';
    }

    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final isSelf = bookingFor == 'self';

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      const Text(
                        'Passenger Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Confirm details for your seat: ${selectedSeats.first}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    bookingFor = 'self';
                                    nameController.text = auth.userName;
                                    phoneController.text = auth.userPhone;
                                    nicController.text = auth.userNic;
                                    primaryGender = auth.userGender.isEmpty
                                        ? 'Male'
                                        : auth.userGender;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelf
                                        ? const Color(0xFF2563EB)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'For Me',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    bookingFor = 'other';
                                    nameController.clear();
                                    phoneController.clear();
                                    nicController.clear();
                                    primaryGender = 'Male';
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !isSelf
                                        ? const Color(0xFF2563EB)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'For Others',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      _buildLabel('Passenger Name'),
                      TextFormField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDec(
                          'Enter passenger\'s full name',
                          Icons.person_outline,
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      _buildLabel('Phone Number'),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDec(
                          'Enter phone number',
                          Icons.phone_android_outlined,
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Phone number is required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      _buildLabel('NIC Number'),
                      TextFormField(
                        controller: nicController,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDec(
                          'e.g. 199912345678 or 991234567V',
                          Icons.badge_outlined,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'NIC is required';
                          }
                          final trimmed = val.trim();
                          final nicRegex = RegExp(r'^([0-9]{9}[vVxX]|[0-9]{12})$');
                          if (!nicRegex.hasMatch(trimmed)) {
                            return 'Invalid NIC format (12 digits or 9 digits with V/X)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _buildLabel('Gender'),
                      DropdownButtonFormField<String>(
                        value: primaryGender,
                        dropdownColor: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: _buildInputDec(
                          'Select Gender',
                          Icons.face_outlined,
                        ),
                        items: ['Male', 'Female']
                            .map(
                              (g) => DropdownMenuItem(
                                value: g,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4.0,
                                  ),
                                  child: Text(
                                    g,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => primaryGender = val);
                          }
                        },
                      ),

                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () {
                            if (!formKey.currentState!.validate()) return;

                            Navigator.pop(context);

                            final Map<String, dynamic> primaryDetails = {
                              'name': nameController.text.trim(),
                              'phone': phoneController.text.trim(),
                              'nic': nicController.text.trim().toUpperCase(),
                              'gender': primaryGender,
                              'booking_type': bookingFor,
                            };

                            final List<Map<String, String>> guests = [];
                            guestGenders.forEach((seat, gender) {
                              guests.add({'seat': seat, 'gender': gender});
                            });

                            final Map<String, dynamic> fullDetails = {
                              'primary': primaryDetails,
                              'guests': guests,
                            };

                            final price = (widget.trip['price'] as num?)?.toDouble() ?? 1600.0;
                            final totalPrice = price * selectedSeats.length;

                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BookingOverviewScreen(
                                  trip: widget.trip,
                                  passengerDetails: fullDetails,
                                  selectedSeats: selectedSeats,
                                  totalPrice: totalPrice,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Review Booking',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _buildInputDec(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.5), size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  void _showGenderSelectionDialog(
    BuildContext context,
    String seatLabel,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Select Passenger for Seat $seatLabel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          ref.read(bookingsProvider.notifier).selectSeatWithGender(seatLabel, 'Male');
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                            border: Border.all(
                              color: const Color(0xFF2563EB),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.face_rounded,
                                color: Color(0xFF2563EB),
                                size: 36,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Male',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          ref.read(bookingsProvider.notifier).selectSeatWithGender(seatLabel, 'Female');
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEC4899).withValues(alpha: 0.2),
                            border: Border.all(
                              color: const Color(0xFFEC4899),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.face_3_rounded,
                                color: Color(0xFFEC4899),
                                size: 36,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Female',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final bookingsState = ref.watch(bookingsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.trip['bus_name'] ?? 'Select Seats',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              widget.trip['reg'] ?? '',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: SeatyBusLoadingIndicator(message: 'Loading available seats...'),
            )
          : Column(
              children: [
                // Realistic Legend Bar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem(const Color(0xFFFFFFFF), 'Available', border: const Color(0xFFCBD5E1)),
                      _buildLegendItem(const Color(0xFF2563EB), 'Male'),
                      _buildLegendItem(const Color(0xFFEC4899), 'Female'),
                      _buildLegendItem(const Color(0xFFD97706), 'Held'),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Seat Grid inside Realistic Bus Chassis Canvas
                Builder(
                  builder: (context) {
                    final layout =
                        widget.trip['seat_layout'] ??
                        {'rows': 10, 'columns': 4, 'aisle_after_column': 2};
                    final int rows = layout['rows'] ?? 10;
                    final int columns = layout['columns'] ?? 4;
                    final int aisleAfter = layout['aisle_after_column'] ?? 2;

                    return Expanded(
                      child: Container(
                        width: double.infinity,
                        color: const Color(0xFFF1F5F9),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 480),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(28),
                                  topRight: Radius.circular(28),
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                                border: Border.all(
                                  color: const Color(0xFFCBD5E1),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                    final double gridHeight = constraints.maxHeight;
                                    final double availableGridHeight = gridHeight - 70.0;
                                    final double rowHeight =
                                        (availableGridHeight / rows).clamp(34.0, 58.0);
                                    final double seatHeight = (rowHeight - 6.0).clamp(28.0, 48.0);
                                    final double seatWidth = (seatHeight * 1.35).clamp(42.0, 58.0);

                                  return Column(
                                    children: [
                                      _buildCabinFront(),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: _buildFlatGrid(
                                          bookingsState,
                                          layout,
                                          rows,
                                          columns,
                                          aisleAfter,
                                          seatWidth,
                                          seatHeight,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Bottom Checkout Bar
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A2540),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, -6),
                      ),
                    ],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bookingsState.selectedSeats.isEmpty
                                    ? 'No seats selected'
                                    : '${bookingsState.selectedSeats.length} Seat${bookingsState.selectedSeats.length > 1 ? 's' : ''} Selected',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if (bookingsState.selectedSeats.isNotEmpty)
                                Text(
                                  bookingsState.selectedSeats.join(', '),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            'Rs. ${((widget.trip['price'] as num) * bookingsState.selectedSeats.length).toDouble().toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: bookingsState.selectedSeats.isEmpty
                            ? null
                            : () => _showPassengerDetailsSheet(context, auth, bookingsState),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF334155),
                          disabledForegroundColor: Colors.white30,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Confirm & Book Seats',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
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

  Widget _buildCabinFront() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // LEFT SIDE: PASSENGER ENTRY DOOR (Sri Lanka RHD Bus Standard)
          const Row(
            children: [
              Icon(
                Icons.sensor_door_rounded,
                color: Color(0xFF10B981),
                size: 16,
              ),
              SizedBox(width: 4),
              Text(
                'ENTRY DOOR',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // CENTER: WINDSHIELD LINE INDICATOR
          Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // RIGHT SIDE: DRIVER CABIN (Sri Lanka Right-Hand Drive)
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'DRIVER CABIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Steering (RHD)',
                    style: TextStyle(color: Color(0xFFFF8A50), fontSize: 9),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.airline_seat_recline_extra_rounded,
                  color: Color(0xFFFF8A50),
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlatGrid(
    BookingsState state,
    Map<String, dynamic> layout,
    int rows,
    int columns,
    int aisleAfter,
    double seatWidth,
    double seatHeight,
  ) {
    final List<dynamic>? customSeatsList = layout['seats'];
    final int gridColumns = aisleAfter > 0 ? columns + 1 : columns;

    return Column(
      children: List.generate(rows, (rIndex) {
        int row = rIndex + 1;
        return Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(gridColumns, (cIndex) {
              Map<String, dynamic>? customSeat;
              if (customSeatsList != null) {
                for (var s in customSeatsList) {
                  if (s is Map && s['row'] == row && s['col'] == cIndex) {
                    customSeat = Map<String, dynamic>.from(s);
                    break;
                  }
                }
              }

              if (customSeat == null) {
                if (aisleAfter > 0 && cIndex == aisleAfter) {
                  return SizedBox(
                    width: seatWidth,
                    child: Center(
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        color: const Color(0xFF94A3B8).withValues(alpha: 0.3),
                        size: 14,
                      ),
                    ),
                  );
                }
                if (customSeatsList != null) {
                  return SizedBox(width: seatWidth);
                }
              }

              int seatColIndex = cIndex;
              bool hasAisleInThisRow = aisleAfter > 0 && rIndex < (rows - 1);
              if (hasAisleInThisRow && cIndex > aisleAfter) {
                seatColIndex = cIndex - 1;
              }

              String seatLabel = (customSeat != null && customSeat['label'] != null)
                  ? customSeat['label'].toString()
                  : '${(rIndex * 4) + seatColIndex + 1}';

              bool isSelected = state.selectedSeats.contains(seatLabel);
              bool isBooked = state.bookedSeats.contains(seatLabel);
              bool isHeld = state.heldSeats.contains(seatLabel);

              String gender = '';
              if (isBooked) {
                gender = state.seatGenders[seatLabel]?.toString() ?? '';
              } else if (isSelected) {
                gender = state.selectedSeatGenders[seatLabel]?.toString() ?? '';
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Animated3DSeat(
                  label: seatLabel,
                  isSelected: isSelected,
                  isBooked: isBooked,
                  isHeld: isHeld,
                  gender: gender,
                  width: seatWidth,
                  height: seatHeight,
                  onTap: () {
                    if (isSelected) {
                      ref.read(bookingsProvider.notifier).deselectSeat(seatLabel);
                    } else {
                      if (state.selectedSeats.length >= 6) {
                        SeatyNotifications.show(
                          context,
                          'Maximum 6 seats allowed per booking session.',
                          isWarning: true,
                        );
                        return;
                      }
                      _showGenderSelectionDialog(context, seatLabel);
                    }
                  },
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildLegendItem(Color color, String label, {Color? border}) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
              color: border ?? Colors.transparent,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
