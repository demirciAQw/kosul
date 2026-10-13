String _two(int v) => v.toString().padLeft(2, '0');

/// 01:07:45
String formatDuration(Duration duration) {
  final d = duration.isNegative ? Duration.zero : duration;
  return '${_two(d.inHours)}:${_two(d.inMinutes.remainder(60))}:${_two(d.inSeconds.remainder(60))}';
}

/// 14:05
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

const _months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// 5 Eki, 14:05
String formatShortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}, ${formatClock(t)}';

/// [12, 13, 14, 17, 20, 21] → "12–14, 17, 20–21"
String formatPages(Iterable<int> pages) {
  final sorted = pages.toSet().toList()..sort();
  if (sorted.isEmpty) return '';
  final parts = <String>[];
  var start = sorted.first, prev = start;
  void flush() => parts.add(start == prev ? '$start' : '$start–$prev');
  for (final p in sorted.skip(1)) {
    if (p == prev + 1) {
      prev = p;
      continue;
    }
    flush();
    start = prev = p;
  }
  flush();
  return parts.join(', ');
}

/// 40 sn, 12 dk, 1,5 sa (yaklaşık süreler için)
String formatApproxDuration(double seconds) {
  if (seconds < 60) return '${seconds.round()} sn';
  if (seconds < 3600) return '${(seconds / 60).round()} dk';
  return '${(seconds / 3600).toStringAsFixed(1).replaceAll('.', ',')} sa';
}

const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
String weekdayShort(DateTime d) => _weekdays[d.weekday - 1];

/// 5 Eki – 18 Eki
String formatDateRange(DateTime a, DateTime b) =>
    '${a.day} ${_months[a.month - 1]} – ${b.day} ${_months[b.month - 1]}';

/// YKS neti: 32,75 (tam sayıysa 32). Negatif olabilir.
String formatNet(double net) {
  final rounded = (net * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  return rounded.toStringAsFixed(2).replaceAll('.', ',');
}

/// 12 Eki 2026
String formatDate(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';

/// 12 Eki
String formatDayMonth(DateTime t) => '${t.day} ${_months[t.month - 1]}';

/// "bugün", "dün", "3 gün önce", "12 Eki"
String formatRelativeDay(DateTime t, DateTime now) {
  final a = DateTime(t.year, t.month, t.day);
  final b = DateTime(now.year, now.month, now.day);
  final days = b.difference(a).inDays;
  if (days <= 0) return 'bugün';
  if (days == 1) return 'dün';
  if (days < 7) return '$days gün önce';
  return formatDayMonth(t);
}
