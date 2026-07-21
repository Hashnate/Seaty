import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:seaty/main.dart';
import 'package:seaty/screens/tracker_screen.dart';

// Sub-Tab 3: Passenger Bookings Tickets List
class PassengerBookingsTab extends ConsumerWidget {
  const PassengerBookingsTab({super.key});

  void _showDownloadTicketDialog(BuildContext context, Map<String, dynamic> b) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.qr_code_2_rounded,
                size: 84,
                color: Color(0xFFE65100),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ready to Board',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0A2540),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ticket Code: TKT-${b['id'].toString().substring(0, 8).toUpperCase()}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 140,
                height: 140,
                child: QrImageView(
                  data: b['id'].toString(),
                  version: QrVersions.auto,
                  size: 140.0,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Show this barcode to the driver/conductor during verification.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.only(
            bottom: 16,
            left: 16,
            right: 16,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _generateAndSavePDF(context, b);
                    },
                    icon: const Icon(
                      Icons.download_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Save PDF',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0A2540),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateAndSavePDF(
    BuildContext context,
    Map<String, dynamic> b,
  ) async {
    try {
      final pdf = pw.Document();
      final ticketCode =
          'TKT-${b['id'].toString().substring(0, 8).toUpperCase()}';
      final seats = (b['seats'] as List).join(', ');
      final formattedPrice =
          double.tryParse(b['price'].toString())?.toStringAsFixed(2) ??
          b['price'].toString();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          build: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'SEATY TRAVELS',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.orange800,
                          borderRadius: pw.BorderRadius.all(
                            pw.Radius.circular(4),
                          ),
                        ),
                        child: pw.Text(
                          'BOARDING PASS',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 1, color: PdfColors.grey300),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'FROM',
                            style: pw.TextStyle(
                              color: PdfColors.grey600,
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            '${b['origin']}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'TO',
                            style: pw.TextStyle(
                              color: PdfColors.grey600,
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            '${b['destination']}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 15),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'DEPARTURE',
                            style: pw.TextStyle(
                              color: PdfColors.grey600,
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            '${b['departure']}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'BUS REG',
                            style: pw.TextStyle(
                              color: PdfColors.grey600,
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            '${b['reg'] ?? 'WP-ND-8942'}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 15),
                  pw.Divider(
                    thickness: 1,
                    color: PdfColors.grey300,
                    borderStyle: pw.BorderStyle.dashed,
                  ),
                  pw.SizedBox(height: 15),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'TICKET CODE',
                            style: pw.TextStyle(
                              color: PdfColors.grey600,
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            ticketCode,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blueGrey800,
                            ),
                          ),
                          pw.SizedBox(height: 10),
                          pw.Text(
                            'SEATS',
                            style: pw.TextStyle(
                              color: PdfColors.grey600,
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            seats,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.orange900,
                            ),
                          ),
                          pw.SizedBox(height: 10),
                          pw.Text(
                            'TOTAL PRICE',
                            style: pw.TextStyle(
                              color: PdfColors.grey600,
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            'Rs. $formattedPrice',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: b['id'].toString(),
                          width: 90,
                          height: 90,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Center(
                    child: pw.Text(
                      'Please show this ticket PDF at the boarding point.',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey500,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$ticketCode.pdf');
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ticket PDF saved to Documents successfully!'),
            backgroundColor: const Color(0xFF00C853),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Bold Gradient Hero Heading ──
            const Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 20),
              child: BoldGradientHeroHeading(
                title: 'My Tickets',
                subtitle: 'Present these digital tickets during boarding.',
              ),
            ),
            const SizedBox(height: 16),

            // ── Ticket Count Badge ──
            if (state.bookings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${state.bookings.length} active ticket${state.bookings.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFFE65100),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // ── Ticket List ──
            Expanded(
              child: state.bookings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.confirmation_num_outlined,
                            size: 56,
                            color: const Color(
                              0xFF0A2540,
                            ).withValues(alpha: 0.12),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No tickets booked yet',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Book a trip to see your tickets here.',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: 110,
                      ),
                      itemCount: state.bookings.length,
                      itemBuilder: (context, index) {
                        final b = state.bookings[index];
                        final ticketCode =
                            'TKT-${b['id'].toString().substring(0, 8).toUpperCase()}';
                        final seats = (b['seats'] as List).join(', ');
                        final formattedPrice =
                            double.tryParse(
                              b['price'].toString(),
                            )?.toStringAsFixed(2) ??
                            b['price'].toString();

                        return GestureDetector(
                          onTap: () => _showDownloadTicketDialog(context, b),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            height: 165,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0A2540,
                                  ).withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Row(
                              children: [
                                // ── Left Block (Orange, Color(0xFFE65100)) ──
                                Expanded(
                                  flex: 4,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFFE65100), // Dark Orange
                                          Color(
                                            0xFF802200,
                                          ), // Deep Burnt Rust Orange
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.directions_bus_rounded,
                                              color: Colors.white70,
                                              size: 24,
                                            ),
                                            const SizedBox(height: 14),
                                            Text(
                                              '${b['origin']}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                                letterSpacing: -0.3,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const Icon(
                                              Icons.arrow_downward_rounded,
                                              color: Colors.white54,
                                              size: 14,
                                            ),
                                            Text(
                                              '${b['destination']}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                                letterSpacing: -0.3,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${b['bus_name']}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // ── Right Block (White, Coords, Cores, Details) ──
                                Expanded(
                                  flex: 6,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Top row: Coords / Seats and QR Code
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${b['departure']}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF0A2540),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 12,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .event_seat_rounded,
                                                        size: 12,
                                                        color:
                                                            const Color(
                                                              0xFF0A2540,
                                                            ).withValues(
                                                              alpha: 0.6,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          'Seats: $seats',
                                                          style: TextStyle(
                                                            color:
                                                                const Color(
                                                                  0xFF0A2540,
                                                                ).withValues(
                                                                  alpha: 0.8,
                                                                ),
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Fare: Rs. $formattedPrice',
                                                    style: const TextStyle(
                                                      color: Color(0xFF0A2540),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            // Small QR code on the right
                                            Container(
                                              width: 52,
                                              height: 52,
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFE2E8F0,
                                                  ),
                                                ),
                                              ),
                                              child: QrImageView(
                                                data: b['id'].toString(),
                                                version: QrVersions.auto,
                                                size: 48.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Bottom Row: Ticket Code & Reg
                                        Container(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              top: BorderSide(
                                                color: Color(0xFFF1F5F9),
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                ticketCode,
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  color: const Color(
                                                    0xFF0A2540,
                                                  ).withValues(alpha: 0.5),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                '${b['reg']}',
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  color: const Color(
                                                    0xFF0A2540,
                                                  ).withValues(alpha: 0.6),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
