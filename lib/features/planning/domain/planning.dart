import '../../../core/utils/id_generator.dart';

int _dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

class PlanTask {
  const PlanTask({
    required this.id,
    required this.planId,
    required this.title,
    this.bookId,
    this.contentNodeId,
    this.targetQuestions,
    this.isDone = false,
  });

  final String id;
  final String planId;
  final String title;
  final String? bookId;
  final String? contentNodeId;
  final int? targetQuestions;
  final bool isDone;
}

/// Tarih aralıklı görev havuzu: "günlük program" dayatmaz; görevler aralık
/// içinde istenen sırayla ve istenen günde yapılır.
class StudyPlan {
  const StudyPlan({
    required this.id,
    required this.title,
    required this.startsOn,
    required this.endsOn,
    required this.createdAt,
    this.tasks = const [],
  });

  final String id;
  final String title;
  final DateTime startsOn;
  final DateTime endsOn;
  final DateTime createdAt;
  final List<PlanTask> tasks;

  int get doneCount => tasks.where((t) => t.isDone).length;
  double get progress => tasks.isEmpty ? 0 : doneCount / tasks.length;

  /// Bitişe kalan gün; bugün son gün ise 0, süre dolduysa negatif.
  int daysUntilEnd(DateTime now) => _dayNumber(endsOn) - _dayNumber(now);
  int daysUntilStart(DateTime now) => _dayNumber(startsOn) - _dayNumber(now);
  bool isExpired(DateTime now) => daysUntilEnd(now) < 0;

  String statusText(DateTime now) {
    final untilStart = daysUntilStart(now);
    final untilEnd = daysUntilEnd(now);
    if (untilStart > 0) return '$untilStart gün sonra başlıyor';
    if (untilEnd < 0) return 'Süresi doldu';
    if (untilEnd == 0) return 'Bugün son gün';
    return '$untilEnd gün kaldı';
  }

  /// Bilgi amaçlı ipucu: kalan görevleri kalan güne bölerek ortalama tempo.
  /// Zorunlu değildir; yalnızca kullanıcıya fikir verir.
  double? paceHint(DateTime now) {
    final remaining = tasks.length - doneCount;
    if (remaining == 0 || isExpired(now)) return null;
    final from = _dayNumber(now) > _dayNumber(startsOn) ? _dayNumber(now) : _dayNumber(startsOn);
    final days = _dayNumber(endsOn) - from + 1;
    return remaining / (days < 1 ? 1 : days);
  }
}

class NewPlanTaskDraft {
  const NewPlanTaskDraft({required this.title, this.bookId, this.contentNodeId, this.targetQuestions});
  final String title;
  final String? bookId;
  final String? contentNodeId;
  final int? targetQuestions;
}

class NewPlanDraft {
  const NewPlanDraft({required this.title, required this.startsOn, required this.endsOn, required this.tasks});
  final String title;
  final DateTime startsOn;
  final DateTime endsOn;
  final List<NewPlanTaskDraft> tasks;
}

class PlanException implements Exception {
  const PlanException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class PlanRepository {
  Stream<List<StudyPlan>> watchPlans();
  Future<void> create(StudyPlan plan);
  Future<void> setTaskDone(String taskId, bool done);
  Future<void> delete(String planId);
}

class CreatePlan {
  CreatePlan(this._repository, this._ids, this._clock);

  final PlanRepository _repository;
  final IdGenerator _ids;
  final Clock _clock;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<StudyPlan> call(NewPlanDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw const PlanException('Plana bir ad ver.');
    final start = _day(draft.startsOn);
    final end = _day(draft.endsOn);
    if (end.isBefore(start)) throw const PlanException('Bitiş tarihi başlangıçtan önce olamaz.');
    if (draft.tasks.isEmpty) throw const PlanException('En az bir görev ekle.');

    final planId = _ids.next();
    final plan = StudyPlan(
      id: planId,
      title: title,
      startsOn: start,
      endsOn: end,
      createdAt: _clock(),
      tasks: [
        for (final t in draft.tasks)
          PlanTask(
            id: _ids.next(),
            planId: planId,
            title: t.title,
            bookId: t.bookId,
            contentNodeId: t.contentNodeId,
            targetQuestions: t.targetQuestions,
          ),
      ],
    );
    await _repository.create(plan);
    return plan;
  }
}
