/// Picks the trip a conductor is actually operating right now.
///
/// Taking `trips.first` is wrong for overnight runs: a 23:00 -> 05:00 journey
/// is still under way after midnight, but the day's trip list by then also
/// contains that night's *next* departure. Priority here is:
///   1. a journey currently under way (from boarding open through arrival)
///   2. otherwise the soonest upcoming departure
///   3. otherwise whatever the list holds
Map<String, dynamic>? pickActiveTrip(List<Map<String, dynamic>> trips) {
  if (trips.isEmpty) return null;
  final now = DateTime.now();

  DateTime? parseWallClock(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw.replaceAll(' ', 'T'));
  }

  Map<String, dynamic>? inProgress;
  Map<String, dynamic>? nextUpcoming;
  DateTime? nextDeparture;

  for (final trip in trips) {
    final departure = parseWallClock(trip['departure']);
    if (departure == null) continue;
    // Fall back to a nominal duration when arrival is missing, so a trip
    // without an arrival time doesn't look like it ends the instant it starts.
    final arrival =
        parseWallClock(trip['arrival']) ?? departure.add(const Duration(hours: 4));
    final boardingOpens = departure.subtract(const Duration(minutes: 30));

    final isUnderWay = !now.isBefore(boardingOpens) && !now.isAfter(arrival);
    if (isUnderWay) {
      inProgress ??= trip;
      continue;
    }

    if (departure.isAfter(now) &&
        (nextDeparture == null || departure.isBefore(nextDeparture))) {
      nextDeparture = departure;
      nextUpcoming = trip;
    }
  }

  return inProgress ?? nextUpcoming ?? trips.first;
}
