import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _generateAndSavePDF(context, b, share: false);
                        },
                        icon: const Icon(
                          Icons.download_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Save PDF',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
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
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _generateAndSavePDF(context, b, share: true);
                        },
                        icon: const Icon(
                          Icons.share_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Share Ticket',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A2540),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
      final seatsList = (b['seats'] as List?)?.join(', ') ?? 'A1';
      final numPassengers = (b['seats'] as List?)?.length ?? 1;
      final formattedPrice =
          double.tryParse(b['price'].toString())?.toStringAsFixed(1) ??
          b['price'].toString();
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

      // 1. Always save directly to user's Documents directory using standard dart:io
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$ticketCode.pdf';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      // 2. Safely trigger native share / layout preview if plugin bindings are loaded
      if (share) {
        try {
          await Printing.sharePdf(bytes: pdfBytes, filename: '$ticketCode.pdf');
        } catch (shareErr) {
          debugPrint('Native share warning: $shareErr');
        }
      } else {
        try {
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => pdfBytes,
            name: ticketCode,
          );
        } catch (layoutErr) {
          debugPrint('Native layout warning: $layoutErr');
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ticket PDF saved to Documents! ($ticketCode.pdf)'),
            backgroundColor: const Color(0xFF10B981),
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
            content: Text('Failed to process PDF: $e'),
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
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${state.bookings.length} active ticket${state.bookings.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
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
                                // ── Left Block (Orange, Color(0xFF2563EB)) ──
                                Expanded(
                                  flex: 4,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFF2563EB), // Dark Orange
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
