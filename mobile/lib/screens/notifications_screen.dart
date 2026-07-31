import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:seaty/main.dart';
import 'package:seaty/widgets/seaty_notifications.dart';

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
    if (noti['type'] == 'booking' ||
        (noti['title'] ?? '').toLowerCase().contains('booking')) {
      Map<String, dynamic>? targetBooking;
      if (bookingsState.bookings.isNotEmpty) {
        final msg = (noti['message'] ?? '').toString();
        for (var b in bookingsState.bookings) {
          final reg = b['reg']?.toString() ?? '';
          final idStr = b['id']?.toString() ?? '';
          if ((reg.isNotEmpty && msg.contains(reg)) ||
              (idStr.isNotEmpty && msg.contains(idStr.substring(0, 8)))) {
            targetBooking = b;
            break;
          }
        }
        targetBooking ??= bookingsState.bookings.first;
      }

      if (targetBooking != null) {
        _showTicketDialog(context, targetBooking);
      } else {
        SeatyNotifications.show(
          context,
          'Opening your tickets...',
        );
      }
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
      backgroundColor: const Color(0xFFF8FAFC), // Modern off-white background
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0A2540),
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        actions: [
          if (unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: () {
                  notificationsNotifier.markAllNotificationsAsRead();
                  SeatyNotifications.show(
                    context,
                    'All notifications marked as read',
                  );
                },
                icon: const Icon(
                  Icons.done_all_rounded,
                  size: 18,
                  color: Color(0xFF0A2540),
                ),
                label: const Text(
                  'Mark all read',
                  style: TextStyle(
                    color: Color(0xFF0A2540),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: list.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 100,
                    width: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2540).withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      size: 48,
                      color: Color(0xFF0A2540),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'All caught up!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0A2540),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No notifications yet. Enjoy your day!',
                    style: TextStyle(
                      fontSize: 14,
                      color: const Color(0xFF0A2540).withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await notificationsNotifier.fetchNotifications();
              },
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
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

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isRead
                          ? Colors.white
                          : const Color(
                              0xFFF1F5F9,
                            ), // Subtle greyish-blue for unread
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: isRead
                            ? Colors.black.withOpacity(0.05)
                            : const Color(0xFF0A2540).withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
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
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _getColorForType(
                                    type,
                                  ).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _getIconForType(type),
                                  color: _getColorForType(type),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: isRead
                                                  ? FontWeight.bold
                                                  : FontWeight.w800,
                                              color: const Color(0xFF0A2540),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          timeAgo,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: const Color(
                                              0xFF0A2540,
                                            ).withOpacity(0.5),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      message,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: const Color(
                                          0xFF0A2540,
                                        ).withOpacity(0.7),
                                        height: 1.4,
                                      ),
                                    ),
                                    if (!isRead)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF2563EB),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Tap to mark as read',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF2563EB),
                                                fontWeight: FontWeight.bold,
                                              ),
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
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
