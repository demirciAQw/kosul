import 'dart:math' as math;

/// SuperMemo-2 (Anki'nin temel aldığı algoritma) zamanlama durumu.
class ReviewState {
  const ReviewState({
    required this.easeFactor,
    required this.intervalDays,
    required this.repetitions,
    required this.dueAt,
    this.lastReviewedAt,
  });

  /// Yeni hata kartı: ertesi "çalışma günü" tekrar edilir.
  factory ReviewState.initial(DateTime now) => ReviewState(
        easeFactor: 2.5,
        intervalDays: 0,
        repetitions: 0,
        dueAt: Sm2Scheduler.dayStart(now, plusDays: 1),
      );

  final double easeFactor;
  final int intervalDays;
  final int repetitions;
  final DateTime dueAt;
  final DateTime? lastReviewedAt;
}

/// "Yanlışlarımı Göster" ekranındaki dört buton → SM-2 kalite puanı (0–5).
enum RecallGrade {
  again(1, 'Tekrar'),
  hard(3, 'Zor'),
  good(4, 'İyi'),
  easy(5, 'Kolay');

  const RecallGrade(this.quality, this.label);
  final int quality;
  final String label;
}

abstract final class Sm2Scheduler {
  static const minEase = 1.3;

  /// Gece 04:00'e kadar yapılan çalışma "önceki gün" sayılır (Anki ile aynı).
  static const dayRolloverHour = 4;

  static ReviewState review(ReviewState s, RecallGrade grade, DateTime now) {
    final q = grade.quality;
    final int repetitions;
    final int interval;
    if (q >= 3) {
      repetitions = s.repetitions + 1;
      interval = switch (repetitions) {
        1 => 1,
        2 => 6,
        _ => (s.intervalDays * s.easeFactor).round(),
      };
    } else {
      repetitions = 0; // unutuldu: baştan
      interval = 1;
    }
    final ease = math.max(minEase, s.easeFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)));
    return ReviewState(
      easeFactor: ease,
      intervalDays: interval,
      repetitions: repetitions,
      dueAt: dayStart(now, plusDays: interval),
      lastReviewedAt: now,
    );
  }

  static DateTime dayStart(DateTime now, {required int plusDays}) {
    final base = now.hour < dayRolloverHour ? now.subtract(const Duration(days: 1)) : now;
    return DateTime(base.year, base.month, base.day + plusDays, dayRolloverHour);
  }
}
