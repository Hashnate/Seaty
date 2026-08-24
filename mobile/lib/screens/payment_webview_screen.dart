import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:seaty/providers/bookings_provider.dart';
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/widgets/seaty_notifications.dart';

/// How the payment ended, from the app's point of view.
///
/// This is the *browser's* view of events, not the source of truth. The backend
/// has already asked Bancstac directly and written the outcome before it
/// redirects here, so the app treats these as a cue to refresh, never as proof
/// of payment. [PaymentOutcome.abandoned] in particular says nothing: the
/// customer may well have paid, and the backend's reconciliation sweeper will
/// pick that up within a minute or two.
enum PaymentOutcome { success, failed, abandoned }

/// Hosts the gateway's card page and watches for the redirect that ends it.
///
/// Bancstac (and the mock gateway) send the browser to
/// `/api/v1/payments/result/{success,failed}` once the backend has verified the
/// transaction. Those two paths are the contract between this screen and
/// `backend/app/routes/payments.py` — if you change one, change the other.
class PaymentWebViewScreen extends ConsumerStatefulWidget {
  final String paymentUrl;
  final String bookingId;
  final double amount;

  const PaymentWebViewScreen({
    super.key,
    required this.paymentUrl,
    required this.bookingId,
    required this.amount,
  });

  @override
  ConsumerState<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends ConsumerState<PaymentWebViewScreen> {
  static const _successPath = '/api/v1/payments/result/success';
  static const _failedPath = '/api/v1/payments/result/failed';

  late final WebViewController _controller;
  bool _loading = true;
  double _progress = 0.0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _progress = progress / 100.0;
                if (progress >= 100) _loading = false;
              });
            }
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _progress = 0.1;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _loading = false;
                _progress = 1.0;
              });
            }
          },
          onNavigationRequest: (request) {
            final path = Uri.tryParse(request.url)?.path ?? '';
            if (path.endsWith(_successPath)) {
              _finish(PaymentOutcome.success);
              return NavigationDecision.prevent;
            }
            if (path.endsWith(_failedPath)) {
              _finish(PaymentOutcome.failed);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            // A sub-resource failing (an image, a font) is not a payment
            // failure. Only a hard failure of the main document is worth
            // surfacing, and even then the payment may have gone through.
            if (!error.isForMainFrame!) return;
            debugPrint('Payment WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<void> _finish(PaymentOutcome outcome) async {
    if (_finished) return; // the delegate can fire more than once
    _finished = true;

    if (outcome == PaymentOutcome.success) {
      // The booking is already confirmed server-side; this just pulls the new
      // state so the ticket is there when the user lands back.
      await ref.read(bookingsProvider.notifier).loadBookings();
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  /// Leaving mid-payment is ambiguous, so say so rather than claiming failure.
  Future<bool> _confirmAbandon() async {
    if (_finished) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 24),
            SizedBox(width: 8),
            Text(
              'Cancel payment?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: const Text(
          'If you have already entered your card details, your payment may '
          'still complete. You can check your tickets in a moment.',
          style: TextStyle(
            color: Color(0xFF475569),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text(
              'Keep Paying',
              style: TextStyle(
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Leave',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  String _formatAmount(double val) {
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final formattedAmount = _formatAmount(widget.amount);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmAbandon() && mounted) {
          Navigator.of(context).pop(PaymentOutcome.abandoned);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF0F172A),
                size: 16,
              ),
            ),
            tooltip: 'Go Back',
            onPressed: () async {
              if (await _confirmAbandon() && mounted) {
                Navigator.of(context).pop(PaymentOutcome.abandoned);
              }
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Secure Checkout',
                style: TextStyle(
                  color: Color(0xFF0A2540),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Commercial Bank of Ceylon',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (await _confirmAbandon() && mounted) {
                  Navigator.of(context).pop(PaymentOutcome.abandoned);
                }
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // Prominent, high-contrast Payable Amount Card
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2540),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0A2540).withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'AMOUNT TO PAY',
                            style: TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      RichText(
                        text: TextSpan(
                          children: [
                            const TextSpan(
                              text: 'LKR ',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: formattedAmount,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.lock_rounded, color: Color(0xFF60A5FA), size: 13),
                        SizedBox(width: 4),
                        Text(
                          '256-Bit SSL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Sleek loading progress bar
            if (_loading)
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                minHeight: 2.5,
              )
            else
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
            // WebView host
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading && _progress < 0.5)
                    Container(
                      color: Colors.white,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                              strokeWidth: 3,
                            ),
                            SizedBox(height: 14),
                            Text(
                              'Connecting to secure banking gateway...',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
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
}

/// Runs the payment flow and reports what happened.
///
/// Kept next to the screen so callers do not have to know about WebViews,
/// result paths, or the difference between "declined" and "we don't know yet".
Future<PaymentOutcome> startPaymentFlow(
  BuildContext context,
  WidgetRef ref, {
  required String paymentUrl,
  required String bookingId,
  required double amount,
}) async {
  final settings = ref.read(settingsProvider);

  // initiate_payment returns a relative URL in mock mode and an absolute
  // Bancstac URL in live mode; both must load.
  final resolved = paymentUrl.startsWith('http')
      ? paymentUrl
      : '${settings.apiBaseUrl.replaceFirst('/api/v1', '')}$paymentUrl';

  final outcome = await Navigator.of(context).push<PaymentOutcome>(
    MaterialPageRoute(
      builder: (_) => PaymentWebViewScreen(
        paymentUrl: resolved,
        bookingId: bookingId,
        amount: amount,
      ),
      fullscreenDialog: true,
    ),
  );

  return outcome ?? PaymentOutcome.abandoned;
}

/// Shows the right message for an outcome. Abandoned is deliberately neither
/// success nor failure — the backend may still confirm it.
void showPaymentOutcome(BuildContext context, PaymentOutcome outcome) {
  switch (outcome) {
    case PaymentOutcome.success:
      SeatyNotifications.show(context, 'Payment successful — your seat is confirmed.');
    case PaymentOutcome.failed:
      SeatyNotifications.show(
        context,
        'Payment was not completed. You have not been charged.',
        isError: true,
      );
    case PaymentOutcome.abandoned:
      SeatyNotifications.show(
        context,
        'Payment not confirmed yet. If you completed it, your ticket will '
        'appear shortly.',
        isWarning: true,
      );
  }
}
