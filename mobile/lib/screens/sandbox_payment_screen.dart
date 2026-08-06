import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:seaty/widgets/seaty_bus_loading.dart';

class SandboxPaymentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> payment;
  final Map<String, dynamic> booking;
  final Map<String, dynamic> trip;

  const SandboxPaymentScreen({
    super.key,
    required this.payment,
    required this.booking,
    required this.trip,
  });

  @override
  ConsumerState<SandboxPaymentScreen> createState() =>
      _SandboxPaymentScreenState();
}

class _SandboxPaymentScreenState extends ConsumerState<SandboxPaymentScreen> {
  late Timer _timer;
  int _secondsRemaining = 600; // 10 minutes hold timer
  bool _isProcessing = false;

  String _formatCurrency(dynamic val, {bool showDecimals = false}) {
    if (val == null) return '0';
    final double numVal = double.tryParse(val.toString()) ?? 0.0;
    if (showDecimals) {
      final parts = numVal.toStringAsFixed(2).split('.');
      final wholeStr = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      return '$wholeStr.${parts[1]}';
    } else {
      final wholeStr = numVal.round().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      return wholeStr;
    }
  }

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timer.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    SeatyNotifications.show(
      context,
      'Seat hold expired. Please try booking again.',
      isError: true,
    );
    Navigator.pop(context);
  }

  Future<void> _processPayment(bool success) async {
    setState(() => _isProcessing = true);
    final bookingsNotifier = ref.read(bookingsProvider.notifier);
    final transactionId = widget.payment['gateway_transaction_id'];

    final bool result = success
        ? await bookingsNotifier.completeSandboxPayment(transactionId)
        : await bookingsNotifier.failSandboxPayment(transactionId);

    if (mounted) {
      setState(() => _isProcessing = false);
      if (result) {
        SeatyNotifications.show(
          context,
          success ? 'Payment Completed Successfully!' : 'Booking cancelled.',
          isError: !success,
          isWarning: !success,
        );
        Navigator.pop(context);
      } else {
        SeatyNotifications.show(
          context,
          'Something went wrong communicating with sandbox server.',
          isError: true,
        );
      }
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatTimer() {
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final selectedSeatsList = List<String>.from(
      widget.booking['selected_seats'] ?? [],
    );
    final double fare =
        double.tryParse(widget.booking['total_price'].toString()) ?? 0.0;
    final double platformFee =
        double.tryParse(widget.payment['platform_fee'].toString()) ?? 25.0;
    final double total =
        double.tryParse(widget.payment['amount'].toString()) ??
        (fare + platformFee);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Seaty Checkout'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hold Timer Capsule
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade200),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.hourglass_bottom_rounded,
                        color: Colors.amber.shade800,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Seats held for ${_formatTimer()}',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Order Details Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.black12),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Booking Summary',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Color(0xFF0A2540),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildRow('Bus Service', widget.trip['bus_name']),
                        _buildRow(
                          'Route',
                          '${widget.trip['origin']} → ${widget.trip['destination']}',
                        ),
                        _buildRow(
                          'Selected Seats',
                          selectedSeatsList.join(', '),
                        ),
                        const Divider(height: 24),
                        _buildRow(
                          'Seat Fare',
                          'Rs. ${_formatCurrency(fare)}',
                        ),
                        _buildRow(
                          'Platform Fee',
                          'Rs. ${_formatCurrency(platformFee)}',
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF0A2540),
                              ),
                            ),
                            Text(
                              'Rs. ${_formatCurrency(total, showDecimals: true)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Sandbox Gateway Action Area
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.security,
                        color: Color(0xFF10B981),
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Secure Sandbox Payment Portal',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'This simulates secure token validation. Click authorize to complete reservation.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(height: 24),
                      if (_isProcessing)
                        const SeatyBusLoadingIndicator(
                          message: 'Authorizing payment transaction...',
                        )
                      else ...[
                        ElevatedButton(
                          onPressed: () => _processPayment(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Authorize & Complete Payment',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => _processPayment(false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                          child: const Text(
                            'Cancel & Release Seats',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0A2540),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
