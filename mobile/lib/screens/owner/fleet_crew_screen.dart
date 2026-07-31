import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seaty/main.dart';
import 'package:seaty/screens/tracker_screen.dart';

class FleetCrewScreen extends ConsumerStatefulWidget {
  final int initialSubTab;
  const FleetCrewScreen({super.key, this.initialSubTab = 0});

  @override
  ConsumerState<FleetCrewScreen> createState() => _FleetCrewScreenState();
}

class _FleetCrewScreenState extends ConsumerState<FleetCrewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialSubTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddConductorDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Add New Conductor',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      hintText: 'e.g. Nimal Perera',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile Phone Number',
                      hintText: 'e.g. 0771234567',
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (nameCtrl.text.isNotEmpty &&
                              phoneCtrl.text.isNotEmpty) {
                            setDialogState(() => isLoading = true);
                            try {
                              await ref
                                  .read(fleetProvider.notifier)
                                  .addConductor(
                                    nameCtrl.text.trim(),
                                    phoneCtrl.text.trim(),
                                  );
                              if (mounted) {
                                Navigator.pop(dialogContext);
                                SeatyNotifications.show(
                                  this.context,
                                  'Conductor added successfully! They can now log in with their phone number.',
                                );
                              }
                            } catch (e) {
                              setDialogState(() => isLoading = false);
                              if (mounted) {
                                SeatyNotifications.show(
                                  this.context,
                                  e.toString().replaceAll('Exception: ', ''),
                                );
                              }
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add Conductor'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fleetState = ref.watch(fleetProvider);
    final vehicles = fleetState.vehicles;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // PROFILE-STYLE BOLD GRADIENT HERO HEADING
            const Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 12),
              child: BoldGradientHeroHeading(
                title: 'Manage Fleet',
                subtitle: '',
              ),
            ),
            const SizedBox(height: 12),

            // TAB BAR SWITCHER
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF2563EB),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF2563EB),
              indicatorWeight: 3,
              dividerHeight: 0,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.directions_bus_rounded),
                  text: 'Buses Fleet',
                ),
                Tab(icon: Icon(Icons.badge_rounded), text: 'Conductors Crew'),
              ],
            ),

            // TAB BAR VIEW
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // SUB-TAB 1: BUSES FLEET
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: vehicles.isNotEmpty ? vehicles.length : 3,
                      itemBuilder: (context, index) {
                        final String busNumber = vehicles.length > index
                            ? (vehicles[index]['registration_number'] ??
                                  'NC-4821')
                            : (index == 0
                                  ? 'NC-4821'
                                  : index == 1
                                  ? 'WP-ND-1234'
                                  : 'BR-9900');
                        final String busModel = vehicles.length > index
                            ? (vehicles[index]['model'] ??
                                  'Leyland Viking Luxury')
                            : 'Leyland Viking Luxury';
                        final String routeName = vehicles.length > index
                            ? (vehicles[index]['route_name'] ??
                                  'Colombo ➔ Kandy')
                            : 'Colombo ➔ Kandy';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF0A2540,
                                ).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.directions_bus_rounded,
                                color: Color(0xFF0A2540),
                                size: 24,
                              ),
                            ),
                            title: Text(
                              busNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  '$busModel • 42 Seats',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Assigned Route: $routeName',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF2563EB),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // SUB-TAB 2: CONDUCTORS CREW
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Crew Directory',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: _showAddConductorDialog,
                              icon: const Icon(
                                Icons.person_add_rounded,
                                size: 16,
                              ),
                              label: const Text('Add Staff'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: fleetState.conductors.isEmpty
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.people_outline_rounded,
                                        size: 48,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        'No conductors added yet',
                                        style: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Tap "Add Staff" to register a conductor',
                                        style: TextStyle(
                                          color: Color(0xFFCBD5E1),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: fleetState.conductors.length,
                                  itemBuilder: (context, index) {
                                    final c = fleetState.conductors[index];
                                    final name =
                                        c['full_name'] ??
                                        c['name'] ??
                                        'Unknown';
                                    final phone =
                                        c['phone_number'] ?? c['phone'] ?? '';

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: const BorderSide(
                                          color: Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.all(
                                          12,
                                        ),
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: const Color(
                                            0xFF0A2540,
                                          ).withOpacity(0.08),
                                          child: const Icon(
                                            Icons.badge_rounded,
                                            color: Color(0xFF0A2540),
                                            size: 20,
                                          ),
                                        ),
                                        title: Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        subtitle: Text('Phone: $phone'),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Text(
                                            'Active',
                                            style: TextStyle(
                                              color: Color(0xFF10B981),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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
    );
  }
}
