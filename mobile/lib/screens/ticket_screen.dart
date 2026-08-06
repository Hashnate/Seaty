import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:seaty/main.dart';
import 'package:seaty/theme/app_theme.dart';
import 'package:seaty/screens/tracker_screen.dart';
import 'package:seaty/widgets/seaty_notifications.dart';

String _formatTicketDate(String? dep) {
  if (dep == null || dep.isEmpty) return 'Jul 28, 2026';
  try {
    final parts = dep.trim().split(' ');
    final dateParts = parts[0].split('-');
    if (dateParts.length == 3) {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      final m = int.parse(dateParts[1]);
      final d = int.parse(dateParts[2]);
      final y = dateParts[0];
      return '${months[m - 1]} $d, $y';
    }
  } catch (e) {
    // fallback
  }
  return dep.split(' ')[0];
}

String _formatTicketTime(String? dep) {
  if (dep == null || dep.isEmpty) return '10:30 AM';
  try {
    final parts = dep.trim().split(' ');
    if (parts.length > 1) {
      final timeParts = parts[1].split(':');
      int h = int.parse(timeParts[0]);
      int m = int.parse(timeParts[1]);
      String period = h >= 12 ? 'PM' : 'AM';
      if (h == 0) {
        h = 12;
      } else if (h > 12) {
        h -= 12;
      }
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
    }
  } catch (e) {
    // fallback
  }
  return '10:30 AM';
}

bool _isTicketPast(Map<String, dynamic> b) {
  final depStr = b['departure']?.toString();
  if (depStr == null || depStr.isEmpty) return false;
  try {
    DateTime? dt;
    final parts = depStr.trim().split(' ');
    if (parts.length >= 2) {
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');
      if (dateParts.length == 3 && timeParts.length >= 2) {
        dt = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
      }
    }
    dt ??= DateTime.tryParse(depStr) ?? DateTime.tryParse(depStr.replaceAll(' ', 'T'));
    if (dt != null) {
      return dt.isBefore(DateTime.now());
    }
  } catch (_) {}
  return false;
}

bool _isTicketCompleted(Map<String, dynamic> b) {
  final status = b['status']?.toString().toLowerCase() ?? '';
  final boarded = b['boarded_seats'] as List?;
  final seats = b['seats'] as List?;
  final isFullyBoarded = boarded != null && seats != null && boarded.isNotEmpty && boarded.length >= seats.length;
  return status == 'completed' || status == 'boarded' || status == 'used' || isFullyBoarded;
}

bool _isTicketExpired(Map<String, dynamic> b) {
  final status = (b['booking_status'] ?? b['status'])?.toString().toLowerCase() ?? '';
  if (status == 'expired' || status == 'cancelled') return true;
  return _isTicketPast(b) && !_isTicketCompleted(b);
}

bool _isTicketPending(Map<String, dynamic> b) {
  final bookingStatus = b['booking_status']?.toString().toLowerCase() ?? '';
  final paymentStatus = b['payment_status']?.toString().toLowerCase() ?? '';
  return (bookingStatus == 'pending' || paymentStatus == 'pending' || paymentStatus == 'awaiting_payment') && !_isTicketExpired(b) && !_isTicketCompleted(b);
}

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

Future<void> _generateAndSavePDF(
  BuildContext context,
  Map<String, dynamic> b, {
  bool share = false,
}) async {
  try {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
    );

    final rawTicketId = b['id'].toString().replaceAll('-', '').toUpperCase();
    final ticketCode = 'TQ${rawTicketId.substring(0, 10)}';
    final pnrCode = 'TS${rawTicketId.substring(0, 16)}/SRILANKA';
    final seatsList = (b['seats'] as List?)?.join(', ') ?? '1';
    final numPassengers = (b['seats'] as List?)?.length ?? 1;
    final formattedPrice = _formatCurrency(b['price']);
    final origin = (b['origin'] ?? 'Colombo Fort').toString();
    final destination = (b['destination'] ?? 'Galle').toString();
    final busName = (b['bus_name'] ?? 'Luxury Express').toString();
    final regNumber = (b['reg'] ?? 'WP-ND-8942').toString();
    final depTimeStr = (b['departure'] ?? '2026-07-27 23:00').toString();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. Top Header Row (Logo + eTICKET + Customer Care)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.red700,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Text(
                          'seaty',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 14),
                      pw.Text(
                        'eTICKET',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Need help with your trip?',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Boarding Point Ph. No: 0775555555 | Seaty Care: 0112345678',
                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 16),

              // 2. Main Trip Summary & QR Code Section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '$origin -> $destination',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        depTimeStr,
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.grey800,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      pw.Text(
                        'Ticket no: $ticketCode',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'PNR no: $pnrCode / $origin TO $destination',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),

                  // QR Code Container
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400, width: 1),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: b['id'].toString(),
                          width: 110,
                          height: 110,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        width: 140,
                        child: pw.Text(
                          'Please show the QR code at the time of boarding for contactless check-in',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 12),

              // Guidelines Banner
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.yellow100,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'Please Note: It is mandatory to follow the travel guidelines of your source and destination state of travel. View Guidelines: https://seaty.lk/travel-guidelines',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.amber900,
                  ),
                ),
              ),
              pw.SizedBox(height: 16),

              // 3. 4-Column Details Table
              pw.Table(
                border: pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5),
                  1: const pw.FlexColumnWidth(2.0),
                  2: const pw.FlexColumnWidth(2.0),
                  3: const pw.FlexColumnWidth(2.5),
                },
                children: [
                  // Row 1: Bus Info, Times & Passenger Count
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(busName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.Text('Luxury Superline ($regNumber)', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('22:45', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.Text('Reporting time', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('23:00', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.Text('Departure time', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('$numPassengers', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.Text('Number of Passengers', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Row 2: Boarding Point Details
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Text('Boarding point details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(origin, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                            pw.Text('Location', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Near Clock Tower', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                            pw.Text('Landmark', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('$origin Bus Terminal Stand #4', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                            pw.Text('Address', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Row 3: Dropping Point Details
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Text('Dropping point details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('05:15', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                            pw.Text('Dropping point time', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Next Day', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                            pw.Text('Dropping point Date', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('$destination Main Central Terminal', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                            pw.Text('Address', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 16),

              // Passenger & Seat Breakdown Table
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    children: [
                      pw.Text('Passenger Details (Name, Gender)', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Seat Number', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 4),
                        child: pw.Text('Primary Passenger (Adult)', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 4),
                        child: pw.Text(seatsList, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 20),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 12),

              // Total Fare Box
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'NOTE : This operator accepts mTicket, you need not carry a print out',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Row(
                        children: [
                          pw.Text('Total Fare : ', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Rs. $formattedPrice', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                        ],
                      ),
                      pw.Text('(Rs. 0 inclusive of GST and service charge, if any)', style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 24),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 10),

              // Footer Guarantee
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'Note: Your booking is covered under Seaty FlexiTicket. You can change your travel date for free up to 8 hours before departure.',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final pdfBytes = await pdf.save();

    // 1. Determine destination directory safely
    Directory? directory;
    try {
      if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getDownloadsDirectory();
      }
    } catch (_) {}
    directory ??= await getApplicationDocumentsDirectory();

    // Ensure directory exists on disk to prevent PathNotFoundException (errno = 2)
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final filePath = '${directory.path}/$ticketCode.pdf';
    final file = File(filePath);
    await file.writeAsBytes(pdfBytes);

    // 2. Safely trigger native share if requested
    if (share) {
      try {
        await Printing.sharePdf(bytes: pdfBytes, filename: '$ticketCode.pdf');
      } catch (shareErr) {
        debugPrint('Native share warning: $shareErr');
      }
    }

    if (context.mounted) {
      SeatyNotifications.show(
        context,
        share ? 'Ticket PDF generated!' : 'Ticket PDF saved successfully! ($ticketCode.pdf)',
      );
    }
  } catch (e) {
    if (context.mounted) {
      SeatyNotifications.show(
        context,
        'Failed to process PDF: $e',
        isError: true,
      );
    }
  }
}

// Sub-Tab 3: Passenger Bookings Tickets List
class PassengerBookingsTab extends ConsumerStatefulWidget {
  const PassengerBookingsTab({super.key});

  @override
  ConsumerState<PassengerBookingsTab> createState() => _PassengerBookingsTabState();
}

class _PassengerBookingsTabState extends ConsumerState<PassengerBookingsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filter Tickets',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (_selectedFilter != 'All')
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedFilter = 'All';
                            });
                            setModalState(() {});
                            Navigator.pop(context);
                          },
                          child: const Text('Reset'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Ticket Status',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: ['All', 'Upcoming', 'Completed'].map((filter) {
                      final isSelected = _selectedFilter == filter;
                      return ChoiceChip(
                        label: Text(filter),
                        selected: isSelected,
                        selectedColor: const Color(0xFF2563EB),
                        backgroundColor: const Color(0xFFF1F5F9),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedFilter = filter;
                            });
                            setModalState(() {});
                            Navigator.pop(context);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingsState = ref.watch(bookingsProvider);

    // Filter bookings list dynamically
    final filteredBookings = bookingsState.bookings.where((b) {
      final origin = (b['origin'] ?? '').toString().toLowerCase();
      final destination = (b['destination'] ?? '').toString().toLowerCase();
      final busName = (b['bus_name'] ?? '').toString().toLowerCase();
      final id = (b['id'] ?? '').toString().toLowerCase();
      final seats = ((b['seats'] as List?)?.join(', ') ?? '').toLowerCase();

      final q = _searchQuery.trim().toLowerCase();
      final matchesSearch = q.isEmpty ||
          origin.contains(q) ||
          destination.contains(q) ||
          busName.contains(q) ||
          id.contains(q) ||
          seats.contains(q);

      if (!matchesSearch) return false;

      final isPast = _isTicketPast(b);
      final isCompleted = _isTicketCompleted(b);

      if (_selectedFilter == 'Upcoming') {
        return !isPast && !isCompleted;
      } else if (_selectedFilter == 'Completed') {
        return isPast || isCompleted;
      }

      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bold Gradient Hero Heading ──
            const Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 16),
              child: BoldGradientHeroHeading(
                title: 'My Tickets',
                subtitle: 'Present these digital tickets during boarding.',
              ),
            ),
            const SizedBox(height: 12),

            // ── Interactive Search & Filter Row ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Search Input Field
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search city, bus, seat or ticket #...',
                          hintStyle: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Filter Tune Button
                  InkWell(
                    onTap: () => _openFilterBottomSheet(context),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: _selectedFilter != 'All'
                            ? const Color(0xFF2563EB)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _selectedFilter != 'All'
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: _selectedFilter != 'All' ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Quick Filter Chips Row ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildFilterChip('All'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Upcoming'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Completed'),
                  const Spacer(),
                  Text(
                    '${filteredBookings.length} ticket${filteredBookings.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Ticket List ──
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF2563EB),
                onRefresh: () async {
                  await ref.read(bookingsProvider.notifier).loadBookings();
                },
                child: filteredBookings.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 80),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0A2540).withValues(alpha: 0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.confirmation_num_outlined,
                                    size: 48,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No matching tickets found'
                                      : 'No tickets available',
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Try searching with a different term'
                                      : 'Book a trip to see your tickets here.',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : AnimationLimiter(
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.only(
                            left: 20,
                            right: 20,
                            bottom: 110,
                          ),
                          itemCount: filteredBookings.length,
                          itemBuilder: (context, index) {
                            final b = filteredBookings[index];
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: SlideAnimation(
                                verticalOffset: 40.0,
                                child: FadeInAnimation(
                                  child: _BoardingPassTicketCard(
                                    booking: b,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        SeatyPageRoute(
                                          page: TicketDetailsScreen(booking: b),
                                        ),
                                      );
                                    },
                                    onShare: () {
                                      _generateAndSavePDF(context, b, share: true);
                                    },
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

// ── Perforated Notched Ticket Divider ──
class TicketPerforationDivider extends StatelessWidget {
  const TicketPerforationDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Semi-Circle Notch
        Container(
          width: 14,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
        ),
        // Center Dashed Perforation Line
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxWidth = constraints.constrainWidth();
              const dashWidth = 5.0;
              const dashSpace = 4.0;
              final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(dashCount, (_) {
                  return const SizedBox(
                    width: dashWidth,
                    height: 1.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFFCBD5E1)),
                    ),
                  );
                }),
              );
            },
          ),
        ),
        // Right Semi-Circle Notch
        Container(
          width: 14,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Ticket Card Widget Matching User Reference Design ──
class _BoardingPassTicketCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onTap;
  final VoidCallback onShare;

  const _BoardingPassTicketCard({
    required this.booking,
    required this.onTap,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final rawTicketId = b['id'].toString().replaceAll('-', '').toUpperCase();
    final ticketCode = rawTicketId.length >= 8 ? rawTicketId.substring(0, 8) : rawTicketId;
    final seats = (b['seats'] as List?)?.join(', ') ?? '1';
    final numSeats = (b['seats'] as List?)?.length ?? 1;
    final formattedPrice = _formatCurrency(b['price']);
    final origin = (b['origin'] ?? 'Trincomalee').toString();
    final destination = (b['destination'] ?? 'Colombo').toString();
    final busName = (b['bus_name'] ?? 'Soyaru Sampath Superline').toString();
    final depTime = _formatTicketTime(b['departure']?.toString());
    final depDate = _formatTicketDate(b['departure']?.toString());

    final isCompleted = _isTicketCompleted(b);
    final isExpired = _isTicketExpired(b);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Top Header Row: Bus Name & Price ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            busName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isExpired ? const Color(0xFF475569) : const Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Ticket #$ticketCode • Seat $seats',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              'Rs. ',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isExpired ? const Color(0xFF64748B) : const Color(0xFF2563EB),
                              ),
                            ),
                            Text(
                              formattedPrice,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: isExpired ? const Color(0xFF64748B) : const Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$numSeats seat${numSeats > 1 ? "s" : ""}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── 2. Middle Route & Duration Graphic Line Row ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Departure Info (Left)
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            depTime,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isExpired ? const Color(0xFF64748B) : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            origin,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Center Connecting Line & Date/Duration Subtitle
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                height: 2,
                                color: isExpired ? const Color(0xFFCBD5E1) : const Color(0xFF93C5FD),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isExpired ? const Color(0xFF94A3B8) : const Color(0xFF2563EB),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isExpired ? const Color(0xFF94A3B8) : const Color(0xFF2563EB),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            depDate,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Destination Info (Right)
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '05:00',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isExpired ? const Color(0xFF64748B) : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            destination,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── 3. Bottom Action / Feature Badges Row ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.event_seat_rounded,
                          size: 15,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Seat $seats',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF059669)),
                                SizedBox(width: 4),
                                Text(
                                  'COMPLETED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF059669),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (isExpired)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFECDD3), width: 1.2),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history_rounded, size: 12, color: Color(0xFFE11D48)),
                                SizedBox(width: 4),
                                Text(
                                  'EXPIRED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFE11D48),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.confirmation_number_rounded, size: 12, color: Color(0xFF2563EB)),
                                SizedBox(width: 4),
                                Text(
                                  'UPCOMING',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF2563EB),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    Row(
                      children: [
                        IconButton(
                          onPressed: onShare,
                          icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF64748B)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: onTap,
                          icon: Icon(
                            (isExpired || isCompleted) ? Icons.remove_red_eye_rounded : Icons.qr_code_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          label: Text(
                            (isExpired || isCompleted) ? 'View' : 'Ticket',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isExpired
                                ? const Color(0xFF64748B)
                                : isCompleted
                                    ? const Color(0xFF059669)
                                    : const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// SEPARATE FULL TICKET DETAILS SCREEN
// =====================================================================
class TicketDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> booking;

  const TicketDetailsScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final ticketCode = 'TKT-${b['id'].toString().substring(0, 8).toUpperCase()}';
    final seats = (b['seats'] as List?)?.join(', ') ?? '';
    final formattedPrice = _formatCurrency(b['price'], showDecimals: true);

    final isExpired = _isTicketExpired(b);
    final isCompleted = _isTicketCompleted(b);
    final isPending = _isTicketPending(b);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ticket #$ticketCode',
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isCompleted
                  ? const Color(0xFFECFDF5)
                  : isExpired
                      ? const Color(0xFFFFF1F2)
                      : isPending
                          ? const Color(0xFFFFFBEB)
                          : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCompleted
                    ? const Color(0xFFA7F3D0)
                    : isExpired
                        ? const Color(0xFFFECDD3)
                        : isPending
                            ? const Color(0xFFFCD34D)
                            : const Color(0xFFBFDBFE),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : isExpired
                          ? Icons.history_rounded
                          : isPending
                              ? Icons.timer_outlined
                              : Icons.confirmation_number_rounded,
                  color: isCompleted
                      ? const Color(0xFF059669)
                      : isExpired
                          ? const Color(0xFFE11D48)
                          : isPending
                              ? const Color(0xFFD97706)
                              : const Color(0xFF2563EB),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  isCompleted
                      ? 'COMPLETED'
                      : isExpired
                          ? 'EXPIRED'
                          : isPending
                              ? 'UNPAID'
                              : 'UPCOMING',
                  style: TextStyle(
                    color: isCompleted
                        ? const Color(0xFF059669)
                        : isExpired
                            ? const Color(0xFFE11D48)
                            : isPending
                                ? const Color(0xFFD97706)
                                : const Color(0xFF2563EB),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Main Digital Ticket Card ──
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0A2540).withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header Bar inside Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.directions_bus_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              b['bus_name'] ?? 'Luxury Bus Service',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          b['reg'] ?? '',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Route & Times Block
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Route Terminals
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                const SizedBox(height: 4),
                                Text(
                                  b['origin'] ?? 'Origin',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            const Icon(
                              Icons.east_rounded,
                              color: Color(0xFF2563EB),
                              size: 22,
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'TO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF94A3B8),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  b['destination'] ?? 'Destination',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 20),

                        // Departure & Seat Info Grid
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'DEPARTURE TIME',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  b['departure'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'SEAT NUMBER(S)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  seats,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TOTAL FARE PAID',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Rs. $formattedPrice',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'BOOKING REF',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ticketCode,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Dashed Cut Line
                        Row(
                          children: List.generate(
                            30,
                            (i) => Expanded(
                              child: Container(
                                height: 1.5,
                                color: i.isEven
                                    ? const Color(0xFFCBD5E1)
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // QR Code Section
                        Center(
                          child: Column(
                            children: [
                              if (isPending)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFFCD34D)),
                                  ),
                                  child: const Column(
                                    children: [
                                      Icon(Icons.timer_outlined, color: Color(0xFFD97706), size: 36),
                                      SizedBox(height: 8),
                                      Text(
                                        'Payment Pending',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E), fontSize: 16),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Boarding QR code will be generated once payment is confirmed.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                  Opacity(
                                    opacity: (isExpired || isCompleted) ? 0.25 : 1.0,
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: (isExpired || isCompleted)
                                              ? const Color(0xFFCBD5E1)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                      child: QrImageView(
                                        data: b['id'].toString(),
                                        version: QrVersions.auto,
                                        size: 160.0,
                                        eyeStyle: QrEyeStyle(
                                          eyeShape: QrEyeShape.square,
                                          color: (isExpired || isCompleted) ? const Color(0xFF64748B) : Colors.black,
                                        ),
                                        dataModuleStyle: QrDataModuleStyle(
                                          dataModuleShape: QrDataModuleShape.square,
                                          color: (isExpired || isCompleted) ? const Color(0xFF64748B) : Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isExpired || isCompleted)
                                    Transform.rotate(
                                      angle: -0.15,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: isExpired ? const Color(0xFFFFF1F2) : const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isExpired ? const Color(0xFFE11D48) : const Color(0xFF059669),
                                            width: 2.0,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (isExpired ? const Color(0xFFE11D48) : const Color(0xFF059669)).withValues(alpha: 0.15),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isExpired ? Icons.history_rounded : Icons.check_circle_rounded,
                                              size: 15,
                                              color: isExpired ? const Color(0xFFE11D48) : const Color(0xFF059669),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              isExpired ? 'EXPIRED' : 'COMPLETED',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                                color: isExpired ? const Color(0xFFE11D48) : const Color(0xFF059669),
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                (isExpired || isCompleted)
                                    ? (isExpired
                                        ? 'This ticket has expired and is no longer valid for boarding.'
                                        : 'Trip completed — thank you for traveling with Seaty!')
                                    : 'Present this QR code to the conductor upon boarding',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (isExpired || isCompleted) ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
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

            const SizedBox(height: 24),

            // ── Download & Share Action Buttons (Hidden for Past / Expired / Completed Tickets) ──
            if (!isExpired && !isCompleted)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _generateAndSavePDF(context, b, share: false);
                      },
                      icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                      label: const Text(
                        'Download PDF',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _generateAndSavePDF(context, b, share: true);
                      },
                      icon: const Icon(Icons.share_rounded, color: Color(0xFF2563EB), size: 18),
                      label: const Text(
                        'Share Ticket',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
