enum MistakeDimension {
  topic('Konu'),
  reason('Neden'),
  subject('Ders');

  const MistakeDimension(this.label);
  final String label;
}

/// Veritabanından gelen ham toplam (anahtar: konu/neden/ders kimliği).
class MistakeStat {
  const MistakeStat({required this.key, required this.count, required this.lostSeconds});
  final String? key;
  final int count;

  /// Tahmini kayıp süre: yanlış sayısı × o testteki soru başına ortalama süre.
  final double lostSeconds;
}

/// Ekranda gösterilecek etiketli hâli.
class LabeledStat {
  const LabeledStat({required this.label, required this.count, required this.lostSeconds, this.sublabel});
  final String label;
  final String? sublabel;
  final int count;
  final double lostSeconds;
}

class DailyStudy {
  const DailyStudy({required this.day, required this.duration});
  final DateTime day;
  final Duration duration;
}

abstract interface class DashboardRepository {
  /// Yalnızca yanlış ve boş kartlar; en çok yapılandan başlayarak.
  Stream<List<MistakeStat>> watchMistakeStats(MistakeDimension by, {DateTime? since});

  /// Bugün dahil son [days] günün toplam çalışma süresi.
  Stream<List<DailyStudy>> watchDailyStudy({required int days, required DateTime today});
}
