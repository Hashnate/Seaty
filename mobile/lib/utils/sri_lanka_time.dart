/// Converts a backend ISO timestamp (which may carry any UTC offset) into a
/// 'YYYY-MM-DD HH:MM:SS' string of Sri Lanka wall-clock digits. Seaty only
/// operates in Sri Lanka, and the rest of the app parses trip time strings
/// via `.replaceAll(' ', 'T')` + `DateTime.parse` (naive, treated as device
/// local time) - this only produces the right wall-clock digits if they're
/// converted to Sri Lanka time first, rather than left in UTC.
String? isoToSriLankaWallClock(dynamic isoValue) {
  if (isoValue == null) return null;
  final parsed = DateTime.tryParse(isoValue.toString());
  if (parsed == null) return null;
  final sriLanka = parsed.toUtc().add(const Duration(hours: 5, minutes: 30));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${sriLanka.year.toString().padLeft(4, '0')}-${two(sriLanka.month)}-${two(sriLanka.day)} '
      '${two(sriLanka.hour)}:${two(sriLanka.minute)}:${two(sriLanka.second)}';
}
