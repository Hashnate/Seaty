import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:seaty/main.dart';
import 'package:seaty/screens/tracker_screen.dart';

class ConductorScanTab extends ConsumerStatefulWidget {
  const ConductorScanTab({super.key});

  @override
  ConsumerState<ConductorScanTab> createState() => _ConductorScanTabState();
}

class _ConductorScanTabState extends ConsumerState<ConductorScanTab> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _manualCodeCtrl = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyTicketCode(String code) async {
    if (_isProcessing || code.trim().isEmpty) return;
    setState(() => _isProcessing = true);

    // Show loading indicator dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFE65100),
        ),
      ),
    );

    final cleanCode = code.trim();
    final state = ref.read(appStateProvider);
    final booking = await state.fetchBookingDetails(cleanCode);

    // Dismiss the loading indicator
    if (mounted) {
      Navigator.pop(context);
    }

    if (booking == null) {
      if (mounted) {
        setState(() => _isProcessing = false);
        SeatyNotifications.show(
          context,
          'Invalid or expired ticket code.',
          isError: true,
        );
      }
      return;
    }

    final passengerName = booking['passenger_name'] ?? 'Passenger';
    final seats = (booking['seats'] as List).join(', ');
    final routeStr = '${booking['origin']} → ${booking['destination']}';
    final status = booking['status']?.toString().toUpperCase() ?? 'PENDING';
    final tripId = booking['trip_id']?.toString() ?? '';

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'TICKET VERIFIED',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF10B981),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Code: #${cleanCode.length > 8 ? cleanCode.substring(0, 8).toUpperCase() : cleanCode.toUpperCase()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _VerifyRow(label: 'Passenger:', value: passengerName),
                const SizedBox(height: 6),
                _VerifyRow(label: 'Seat Number:', value: seats),
                const SizedBox(height: 6),
                _VerifyRow(label: 'Route:', value: routeStr),
                const SizedBox(height: 6),
                _VerifyRow(label: 'Payment Status:', value: status),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      setState(() => _isProcessing = true);
                      
                      // Toggle boarding for all seats in this booking
                      final List<String> bookingSeats = List<String>.from(booking['seats'] ?? []);
                      for (final seat in bookingSeats) {
                        await state.toggleBoarding(tripId, seat);
                      }
                      
                      if (mounted) {
                        setState(() => _isProcessing = false);
                        _manualCodeCtrl.clear();
                        SeatyNotifications.show(
                          context,
                          'Passenger boarded successfully!',
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Confirm Boarding',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _isProcessing = false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

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
                  title: 'Verify Ticket',
                  subtitle: 'Scan passenger QR ticket or enter 6-digit code.',
                ),
              ),
              const SizedBox(height: 16),

              // Camera Scanner Box
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 260,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        MobileScanner(
                          controller: _scannerController,
                          onDetect: (capture) {
                            final List<Barcode> barcodes = capture.barcodes;
                            for (final barcode in barcodes) {
                              if (barcode.rawValue != null) {
                                _verifyTicketCode(barcode.rawValue!);
                                break;
                              }
                            }
                          },
                        ),

                        // Overlay Finder Frame
                        Center(
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE65100),
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),

                        // Flash & Camera controls
                        Positioned(
                          top: 12,
                          right: 12,
                          child: CircleAvatar(
                            backgroundColor: Colors.black45,
                            child: IconButton(
                              icon: const Icon(
                                Icons.flash_on_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () =>
                                  _scannerController.toggleTorch(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Manual Code Verification Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Manual Code Verification',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter 6-digit booking reference printed on ticket.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _manualCodeCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'e.g. ST-8942',
                                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                                prefixIcon: const Icon(
                                  Icons.confirmation_number_outlined,
                                  color: Color(0xFF64748B),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () =>
                                  _verifyTicketCode(_manualCodeCtrl.text),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE65100),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                              ),
                              child: const Text(
                                'Verify',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifyRow extends StatelessWidget {
  final String label;
  final String value;
  const _VerifyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
