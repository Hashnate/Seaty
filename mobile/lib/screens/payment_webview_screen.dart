import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:seaty/providers/bookings_provider.dart';
import 'package:seaty/providers/shared_providers.dart';
import 'package:seaty/theme/app_colors.dart';
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
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
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
        title: const Text('Cancel payment?'),
        content: const Text(
          'If you have already entered your card details, your payment may '
          'still complete. You can check your tickets in a moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep paying'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmAbandon() && mounted) {
          Navigator.of(context).pop(PaymentOutcome.abandoned);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text('Pay LKR ${widget.amount.toStringAsFixed(2)}'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await _confirmAbandon() && mounted) {
                Navigator.of(context).pop(PaymentOutcome.abandoned);
              }
            },
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const ColoredBox(
                color: Colors.white,
                child: Center(child: CircularProgressIndicator()),
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
