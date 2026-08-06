import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:seaty/main.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:seaty/screens/tracker_screen.dart';
import 'package:seaty/screens/ticket_screen.dart';
import 'package:seaty/screens/profile_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  String _formatTimeAgo(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return 'Just now';
    try {
      final DateTime parsed = DateTime.parse(dateTimeStr).toLocal();
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(parsed);

      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return 'Recent';
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'booking':
        return Icons.confirmation_number_rounded;
      case 'trip_update':
        return Icons.event_note_rounded;
      case 'verification':
        return Icons.verified_user_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'booking':
        return const Color(0xFF2563EB); // Matte Orange
      case 'trip_update':
        return const Color(0xFF0A2540); // Navy Blue
      case 'verification':
        return const Color(0xFF10B981); // Emerald Green
      default:
        return const Color(0xFF64748B); // Slate Grey
    }
  }

  void _handleNotificationTap(
      BuildContext context, BookingsState bookingsState, Map<String, dynamic> noti) {
    final type = (noti['type'] ?? '').toString().toLowerCase();
    final title = (noti['title'] ?? '').toString().toLowerCase();
    final message = (noti['message'] ?? '').toString().toLowerCase();

    // 1. Profile / Account / Verification Notifications
    if (type == 'verification' || type == 'profile' || title.contains('profile') || title.contains('account')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ProfileEditScreen()),
      );
      return;
    }

    // 2. Booking / Ticket Lookup
    Map<String, dynamic>? targetBooking;
    if (bookingsState.bookings.isNotEmpty) {
      for (var b in bookingsState.bookings) {
        final reg = b['reg']?.toString() ?? '';
        final idStr = b['id']?.toString() ?? '';
        if ((reg.isNotEmpty && message.contains(reg.toLowerCase())) ||
            (idStr.isNotEmpty && message.contains(idStr.substring(0, 8).toLowerCase()))) {
          targetBooking = b;
          break;
        }
      }
      targetBooking ??= bookingsState.bookings.first;
    }

    // 3. Live Tracking / GPS Notifications
    if (type == 'tracker' || type == 'trip_update' || title.contains('tracker') || title.contains('trip') || message.contains('tracking') || message.contains('live location')) {
      if (targetBooking != null) {
        final tripData = targetBooking['trip'] is Map<String, dynamic>
            ? targetBooking['trip'] as Map<String, dynamic>
            : targetBooking;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PassengerTrackingTab(trip: tripData)),
        );
        return;
      }
    }

    // 4. Ticket Details / Booking Screen Navigation
    if (targetBooking != null) {
      if (type == 'booking' || title.contains('booking')) {
        _showTicketDialog(context, targetBooking);
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TicketDetailsScreen(booking: targetBooking!),
        ),
      );
    } else {
      SeatyNotifications.show(
        context,
        noti['message'] ?? 'Notification details unavailable.',
      );
    }
  }

  void _showTicketDialog(BuildContext context, Map<String, dynamic> b) {
    final ticketCode =
        'TKT-${b['id'].toString().substring(0, 8).toUpperCase()}';
    final seats = (b['seats'] as List?)?.join(', ') ?? '';
    final formattedPrice =
        double.tryParse(b['price'].toString())?.toStringAsFixed(2) ??
        b['price'].toString();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.confirmation_number_rounded, color: Color(0xFF2563EB), size: 24),
              SizedBox(width: 8),
              Text(
                'Digital Boarding Pass',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0A2540),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            ticketCode,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0A2540),
                              fontSize: 12,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'CONFIRMED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Text(
                        '${b['origin']} ➔ ${b['destination']}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0A2540),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Departure: ${b['departure']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Bus: ${b['bus_name']} (${b['reg']})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Seat(s): $seats',
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Rs. $formattedPrice',
                            style: const TextStyle(
                              color: Color(0xFF0A2540),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox(
                    width: 150,
                    height: 150,
                    child: QrImageView(
                      data: b['id'].toString(),
                      version: QrVersions.auto,
                      size: 150.0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Show this QR ticket to the conductor when boarding.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsState = ref.watch(notificationsProvider);
    final notificationsNotifier = ref.read(notificationsProvider.notifier);
    final bookingsState = ref.watch(bookingsProvider);
    final list = notificationsState.notifications;
    final unreadCount = notificationsState.unreadNotificationsCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bold Gradient Hero Heading matching other main screens ──
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: BoldGradientHeroHeading(
                      title: 'Notifications',
                      subtitle: 'Real-time booking, trip, and platform alerts.',
                    ),
                  ),
                  if (unreadCount > 0)
                    GestureDetector(
                      onTap: () {
                        notificationsNotifier.markAllNotificationsAsRead();
                        SeatyNotifications.show(
                          context,
                          'All notifications marked as read',
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.done_all_rounded,
                              size: 14,
                              color: Color(0xFF2563EB),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Mark read',
                              style: TextStyle(
                                color: Color(0xFF2563EB),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Unread Badge Pill Count ──
            if (unreadCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (unreadCount > 0) const SizedBox(height: 12),

            // ── Notification List Body ──
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 88,
                            width: 88,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A2540).withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.notifications_none_rounded,
                              size: 42,
                              color: Color(0xFF94A3B8),
                            ),
                          ).animate().scale(duration: 450.ms, curve: Curves.easeOutBack),
                          const SizedBox(height: 16),
                          const Text(
                            'All caught up!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'No notifications yet. Enjoy your day!',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF2563EB),
                      onRefresh: () async {
                        await notificationsNotifier.fetchNotifications();
                      },
                      child: AnimationLimiter(
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.only(
                            left: 20,
                            right: 20,
                            bottom: 110,
                          ),
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final noti = list[index];
                            final String notiId = noti['id']?.toString() ?? '';
                            final String title = noti['title'] ?? 'Alert';
                            final String message = noti['message'] ?? '';
                            final String type = noti['type'] ?? 'system';
                            final bool isRead =
                                noti['is_read'] == true || noti['is_read'] == 1;
                            final String timeAgo = _formatTimeAgo(noti['created_at']);

                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 350),
                              child: SlideAnimation(
                                verticalOffset: 30.0,
                                child: FadeInAnimation(
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isRead
                                            ? const Color(0xFFE2E8F0)
                                            : const Color(0xFFBFDBFE),
                                        width: isRead ? 1.0 : 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.03),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            if (!isRead && notiId.isNotEmpty) {
                                              notificationsNotifier.markNotificationAsRead(notiId);
                                            }
                                            _handleNotificationTap(context, bookingsState, noti);
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Icon Badge
                                                Container(
                                                  padding: const EdgeInsets.all(10),
                                                  decoration: BoxDecoration(
                                                    color: _getColorForType(type).withValues(alpha: 0.1),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    _getIconForType(type),
                                                    color: _getColorForType(type),
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                // Body Text Column
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              title,
                                                              style: TextStyle(
                                                                fontSize: 14.5,
                                                                fontWeight: isRead
                                                                    ? FontWeight.w700
                                                                    : FontWeight.w900,
                                                                color: const Color(0xFF0F172A),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            timeAgo,
                                                            style: const TextStyle(
                                                              fontSize: 11.5,
                                                              color: Color(0xFF94A3B8),
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        message,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Color(0xFF475569),
                                                          height: 1.4,
                                                        ),
                                                      ),
                                                      if (!isRead) ...[
                                                        const SizedBox(height: 8),
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
                                                            const SizedBox(width: 6),
                                                            const Text(
                                                              'Tap to view details',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Color(0xFF2563EB),
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                          ],
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
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
