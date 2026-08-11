/// Small string helpers that keep display formatting from throwing.
///
/// These preserve existing output for well-formed values - a 36-character UUID
/// yields exactly what `substring(0, n)` yielded before. They only change
/// behaviour for the malformed/short input that used to raise a RangeError.

/// First [length] characters of [value], or the whole thing if it is shorter.
///
/// `null` and empty values collapse to [fallback] rather than the literal
/// string "null" that `value.toString()` would otherwise produce.
String shortId(dynamic value, int length, {String fallback = '--------'}) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty || raw.toLowerCase() == 'null') return fallback;
  return raw.length <= length ? raw : raw.substring(0, length);
}

/// Upper-cases the first character without assuming there is one.
String capitalize(String value, {String fallback = ''}) {
  if (value.isEmpty) return fallback;
  return value[0].toUpperCase() + value.substring(1);
}
