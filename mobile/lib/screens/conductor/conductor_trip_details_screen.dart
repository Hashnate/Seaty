import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:seaty/main.dart';
import 'package:seaty/widgets/seaty_notifications.dart';
import 'package:seaty/widgets/seaty_bus_loading.dart';

class ConductorTripDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> trip;
  const ConductorTripDetailsScreen({super.key, required this.trip});

  @override
  ConsumerState<ConductorTripDetailsScreen> createState() =>
      _ConductorTripDetailsScreenState();
}

class _ConductorTripDetailsScreenState
    extends ConsumerState<ConductorTripDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _manifestData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    ref.read(gpsTrackingProvider.notifier).stopStreamingGPS();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final bookingsNotifier = ref.read(bookingsProvider.notifier);
    await bookingsNotifier.loadSeatAvailability(widget.trip['id'].toString(), clearFirst: true);
    final manifest = await bookingsNotifier.fetchTripManifest(
      widget.trip['id'].toString(),
    );
    if (mounted) {
      setState(() {
        _manifestData = manifest;
        _isLoading = false;
      });
      _checkAndStartGpsStreaming();
    }
  }

  Future<void> _checkAndStartGpsStreaming() async {
    final gpsNotifier = ref.read(gpsTrackingProvider.notifier);
    final gpsState = ref.read(gpsTrackingProvider);
    final departureStr = widget.trip['departure'];
    final arrivalStr = widget.trip['arrival'];
    final vehicleId = widget.trip['vehicle_id']?.toString() ?? '';

    if (departureStr == null || vehicleId.isEmpty) return;

    try {
      final departureTime = DateTime.parse(departureStr.replaceAll(' ', 'T'));
      final now = DateTime.now();
      final startTime = departureTime.subtract(const Duration(minutes: 30));

      final arrivalTime = (arrivalStr != null && arrivalStr.toString().isNotEmpty)
          ? DateTime.parse(arrivalStr.toString().replaceAll(' ', 'T'))
          : departureTime.add(const Duration(hours: 4)); // Fallback duration

      if (now.isAfter(startTime) && now.isBefore(arrivalTime)) {
        if (!gpsState.isStreamingGPS) {
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
          LocationPermission permission = await Geolocator.checkPermission();

          if (!serviceEnabled || permission == LocationPermission.denied) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF0A2540),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    'GPS Broadcast Required',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  content: const Text(
                    'Live tracking is now active for this ride. Please enable GPS so passengers can view your bus in real-time.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Later', style: TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await gpsNotifier.startStreamingGPS(vehicleId, true);
                        if (mounted) {
                          SeatyNotifications.show(
                            context,
                            'GPS Tracking Started Successfully',
                          );
                        }
                      },
                      child: const Text('Start Broadcast'),
                    ),
                  ],
                ),
              );
            }
          } else {
            await gpsNotifier.startStreamingGPS(vehicleId, true);
            if (mounted) {
              SeatyNotifications.show(
                context,
                'GPS Location Broadcast Started Automatically',
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error starting GPS stream in conductor trip: $e');
    }
  }

  String _formatRemainingTime(int totalMinutes) {
    if (totalMinutes < 0) return '0m';
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return '${hours}h ${mins}m';
    }
    return '${totalMinutes}m';
  }

  void _showPassengerDetails(
    Map<String, dynamic> passenger,
    List<String> boardedSeats,
  ) {
    bool isBoarded = boardedSeats.contains(passenger['seat']);

    final departureStr = widget.trip['departure'];
    bool isBoardingAvailable = true;
    String disabledReason = "";
    if (departureStr != null) {
      try {
        final departureTime = DateTime.parse(departureStr.replaceAll(' ', 'T'));
        final now = DateTime.now();
        final difference = departureTime.difference(now);
        if (difference.inMinutes > 30) {
          isBoardingAvailable = false;
          disabledReason = "Boarding opens 30 minutes before departure. Departure is in ${_formatRemainingTime(difference.inMinutes)} (at $departureStr).";
        }
      } catch (e) {
        debugPrint('Error parsing departure time: $e');
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2540),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Seat ${passenger['seat']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('Name', passenger['name']),
                        _buildDetailRow(
                          'Gender',
                          passenger['gender'].toString().toUpperCase(),
                        ),
                        _buildDetailRow(
                          'Phone',
                          passenger['phone'].toString().isEmpty
                              ? 'N/A'
                              : passenger['phone'],
                        ),
                        _buildDetailRow(
                          'Booking ID',
                          passenger['booking_id'].toString().substring(0, 8) +
                              '...',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: (isBoarded || isBoardingAvailable)
                        ? () async {
                            try {
                              final updatedBoarded = await ref.read(bookingsProvider.notifier).toggleBoarding(
                                widget.trip['id'].toString(),
                                passenger['seat'],
                              );
                              if (updatedBoarded != null) {
                                setState(() {
                                  _manifestData!['boarded_seats'] = updatedBoarded;
                                });
                                setModalState(() {
                                  isBoarded = updatedBoarded.contains(
                                    passenger['seat'],
                                  );
                                });
                                if (mounted) Navigator.pop(context);
                                SeatyNotifications.show(
                                  context,
                                  isBoarded
                                      ? 'Passenger Marked as Boarded'
                                      : 'Boarding Undone',
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                Navigator.pop(context);
                                final errorMsg = e.toString().replaceFirst('Exception: ', '');
                                SeatyNotifications.show(
                                  context,
                                  errorMsg,
                                  isError: true,
                                );
                              }
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBoarded
                          ? Colors.red.shade400
                          : isBoardingAvailable
                              ? const Color(0xFF2E7D32)
                              : Colors.grey,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isBoarded
                          ? 'Undo Boarding'
                          : isBoardingAvailable
                              ? 'Mark as Boarded'
                              : 'Boarding Locked',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!isBoarded && !isBoardingAvailable) ...[
                    const SizedBox(height: 12),
                    Text(
                      disabledReason,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red.shade200,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingsState = ref.watch(bookingsProvider);
    final gpsState = ref.watch(gpsTrackingProvider);
    final gpsNotifier = ref.read(gpsTrackingProvider.notifier);
    final layout =
        widget.trip['seat_layout'] ??
        {'rows': 10, 'columns': 4, 'aisle_after_column': 2};
    final int rows = layout['rows'] ?? 10;
    final int columns = layout['columns'] ?? 4;
    final int aisleAfter = layout['aisle_after_column'] ?? 2;
    final int gridColumns = aisleAfter > 0 ? columns + 1 : columns;
    final int totalGridItems = rows * gridColumns;
    final List<dynamic>? customSeatsList = layout['seats'];

    List<String> boardedSeats = _manifestData != null
        ? List<String>.from(_manifestData!['boarded_seats'] ?? [])
        : [];
    List<dynamic> manifestList = _manifestData != null
        ? _manifestData!['manifest'] ?? []
        : [];

    int totalBooked = bookingsState.bookedSeats.length;
    int totalBoarded = boardedSeats.length;
    int capacity = widget.trip['total_seats'] ?? 40;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                gpsState.isStreamingGPS ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                color: gpsState.isStreamingGPS ? const Color(0xFF10B981) : Colors.black38,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                gpsState.isStreamingGPS ? 'LIVE ON' : 'LIVE OFF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: gpsState.isStreamingGPS ? const Color(0xFF10B981) : Colors.black38,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 4),
              Switch(
                value: gpsState.isStreamingGPS,
                activeColor: const Color(0xFF10B981),
                activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.black12,
                onChanged: (bool value) async {
                  final vehicleId = widget.trip['vehicle_id']?.toString() ?? '';
                  if (vehicleId.isEmpty) return;

                  if (value) {
                    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                    LocationPermission permission = await Geolocator.checkPermission();

                    if (!serviceEnabled || permission == LocationPermission.denied) {
                      _checkAndStartGpsStreaming();
                    } else {
                      await gpsNotifier.startStreamingGPS(vehicleId, true);
                    }
                  } else {
                    gpsNotifier.stopStreamingGPS();
                  }
                },
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: SeatyBusLoadingIndicator(message: 'Loading manifest & passenger details...'),
            )
          : Column(
              children: [
                // Summary Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF0A2540),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat('Capacity', capacity.toString(), Colors.white),
                      _buildStat(
                        'Booked',
                        totalBooked.toString(),
                        Colors.blue.shade200,
                      ),
                      _buildStat(
                        'Boarded',
                        totalBoarded.toString(),
                        Colors.green.shade400,
                      ),
                    ],
                  ),
                ),

                // Legend
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem(
                        const Color(0xFFF4F6F9),
                        'Empty',
                        border: Colors.black12,
                      ),
                      _buildLegendItem(const Color(0xFF0F2C59), 'Male'),
                      _buildLegendItem(const Color(0xFFF472B6), 'Female'),
                      _buildLegendItem(const Color(0xFF2E7D32), 'Boarded'),
                    ],
                  ),
                ),

                // Bus Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(28),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridColumns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: totalGridItems,
                    itemBuilder: (context, index) {
                      int colIndex = index % gridColumns;
                      int row = index ~/ gridColumns + 1;

                      Map<String, dynamic>? customSeat;
                      if (customSeatsList != null) {
                        for (var s in customSeatsList) {
                          if (s is Map &&
                              s['row'] == row &&
                              s['col'] == colIndex) {
                            customSeat = Map<String, dynamic>.from(s);
                            break;
                          }
                        }
                        if (customSeat == null) {
                          if (aisleAfter > 0 && colIndex == aisleAfter) {
                            return const Center(
                              child: Icon(
                                Icons.unfold_more,
                                color: Colors.black12,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                      } else {
                        if (aisleAfter > 0 && colIndex == aisleAfter) {
                          return const Center(
                            child: Icon(
                              Icons.unfold_more,
                              color: Colors.black12,
                            ),
                          );
                        }
                      }

                      int seatColIndex = colIndex;
                      if (customSeat == null &&
                          aisleAfter > 0 &&
                          colIndex > aisleAfter) {
                        seatColIndex = colIndex - 1;
                      }
                      String seatLabel = customSeat != null
                          ? customSeat['label']
                          : '${(row - 1) * columns + seatColIndex + 1}';

                      bool isBooked = bookingsState.bookedSeats.contains(seatLabel);
                      bool isBoarded = boardedSeats.contains(seatLabel);

                      Color seatColor = const Color(0xFFF4F6F9);
                      Color textColor = const Color(0xFF0A2540);
                      Color borderColor = Colors.black12;

                      if (isBoarded) {
                        seatColor = const Color(0xFF2E7D32);
                        textColor = Colors.white;
                        borderColor = const Color(0xFF2E7D32);
                      } else if (isBooked) {
                        final gender =
                            bookingsState.seatGenders[seatLabel]?.toLowerCase() ?? '';
                        if (gender == 'male') {
                          seatColor = const Color(0xFF0F2C59);
                          textColor = Colors.white;
                          borderColor = const Color(0xFF0F2C59);
                        } else if (gender == 'female') {
                          seatColor = const Color(0xFFF472B6);
                          textColor = Colors.white;
                          borderColor = const Color(0xFFF472B6);
                        } else {
                          seatColor = Colors.grey.shade400;
                          textColor = Colors.white;
                          borderColor = Colors.grey.shade500;
                        }
                      }

                      return InkWell(
                        onTap: isBooked
                            ? () {
                                // Find passenger in manifest
                                final passenger = manifestList.firstWhere(
                                  (p) => p['seat'] == seatLabel,
                                  orElse: () => <String, dynamic>{},
                                );
                                if (passenger.isNotEmpty) {
                                  _showPassengerDetails(
                                    passenger,
                                    boardedSeats,
                                  );
                                } else {
                                  SeatyNotifications.show(
                                    context,
                                    'Passenger details not found in manifest.',
                                  );
                                }
                              }
                            : null,
                        child: Container(
                          decoration: BoxDecoration(
                            color: seatColor,
                            border: Border.all(color: borderColor, width: 1.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            seatLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
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
            border: Border.all(color: border ?? Colors.transparent),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
