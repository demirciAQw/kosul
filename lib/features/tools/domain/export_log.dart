/// Claude'a gönderilen bir paket: hangi aralığın verisi, ne kadarı.
class ClaudeBatch {
  const ClaudeBatch({
    required this.number,
    required this.at,
    required this.full,
    required this.questions,
    required this.sessions,
    this.from,
  });

  final int number;
  final DateTime at; // gönderim anı (bir sonraki "yeni veriler" paketinin başlangıcı)
  final DateTime? from; // null = baştan beri
  final bool full; // tüm veri mi, yalnızca yeniler mi
  final int questions;
  final int sessions;

  String get label => 'Paket #$number';

  Map<String, dynamic> toJson() => {
        'number': number,
        'at': at.toIso8601String(),
        if (from != null) 'from': from!.toIso8601String(),
        'full': full,
        'questions': questions,
        'sessions': sessions,
      };

  static ClaudeBatch? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['at'] is String ? DateTime.tryParse(j['at'] as String) : null;
    final n = j['number'];
    if (at == null || n is! int) return null;
    return ClaudeBatch(
      number: n,
      at: at,
      from: j['from'] is String ? DateTime.tryParse(j['from'] as String) : null,
      full: j['full'] == true,
      questions: j['questions'] is int ? j['questions'] as int : 0,
      sessions: j['sessions'] is int ? j['sessions'] as int : 0,
    );
  }
}

/// Bir kaydın hangi pakette gönderildiği: oluşturulma anı paketin aralığına düşüyorsa.
ClaudeBatch? batchOf(DateTime createdAt, List<ClaudeBatch> log) {
  for (final b in log) {
    final from = b.from;
    if (!createdAt.isAfter(b.at) && (from == null || createdAt.isAfter(from))) return b;
  }
  return null;
}

/// Bir sonraki "yeni veriler" paketinin başlangıcı: son gönderim anı.
DateTime? nextSince(List<ClaudeBatch> log) => log.isEmpty ? null : log.map((b) => b.at).reduce((a, b) => a.isAfter(b) ? a : b);
