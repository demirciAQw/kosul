import '../../../core/utils/id_generator.dart';

int _dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

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

/// Hazır plan türleri: tarih aralığını ve önerilen adı belirler.
enum PlanKind {
  weekly('Haftalık'),
  monthly('Aylık'),
  yearly('Yıllık'),
  custom('Özel');

  const PlanKind(this.label);
  final String label;

  /// [today] dahil aralık: haftalık 7 gün, aylık bir ay, yıllık bir yıl.
  ({DateTime start, DateTime end}) rangeFrom(DateTime today) {
    final start = _day(today);
    return switch (this) {
      PlanKind.weekly => (start: start, end: start.add(const Duration(days: 6))),
      PlanKind.monthly => (start: start, end: DateTime(start.year, start.month + 1, start.day - 1)),
      PlanKind.yearly => (start: start, end: DateTime(start.year + 1, start.month, start.day - 1)),
      PlanKind.custom => (start: start, end: start.add(const Duration(days: 13))),
    };
  }
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
    this.completedAt,
    this.tasks = const [],
  });

  final String id;
  final String title;
  final DateTime startsOn;
  final DateTime endsOn;
  final DateTime createdAt;

  /// "Tamamladım" işaretlendiği an; null = sürüyor.
  final DateTime? completedAt;
  final List<PlanTask> tasks;

  bool get isCompleted => completedAt != null;
  int get doneCount => tasks.where((t) => t.isDone).length;
  bool get allTasksDone => tasks.isNotEmpty && doneCount == tasks.length;
  double get progress => isCompleted ? 1 : (tasks.isEmpty ? 0 : doneCount / tasks.length);

  /// Bitişe kalan gün; bugün son gün ise 0, süre dolduysa negatif.
  int daysUntilEnd(DateTime now) => _dayNumber(endsOn) - _dayNumber(now);
  int daysUntilStart(DateTime now) => _dayNumber(startsOn) - _dayNumber(now);
  bool isExpired(DateTime now) => daysUntilEnd(now) < 0;

  String statusText(DateTime now) {
    if (isCompleted) return 'Tamamlandı';
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
    if (isCompleted || remaining == 0 || isExpired(now)) return null;
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

  /// Planı ve görevlerini (tamamlanma durumlarıyla) yazar. Silmeyi geri almak için de kullanılır.
  Future<void> create(StudyPlan plan);
  Future<void> addTasks(String planId, List<PlanTask> tasks);
  Future<void> setTaskDone(String taskId, bool done);
  Future<void> deleteTask(String taskId);
  Future<void> setCompleted(String planId, DateTime? completedAt);
  Future<void> update(String planId, {required String title, required DateTime startsOn, required DateTime endsOn});
  Future<void> renameTask(String taskId, String title);
  Future<void> delete(String planId);
}

/// Planın adını ve tarih aralığını düzeltir.
class EditPlan {
  EditPlan(this._repository);
  final PlanRepository _repository;

  Future<void> call(String planId, {required String title, required DateTime startsOn, required DateTime endsOn}) {
    final t = title.trim();
    if (t.isEmpty) throw const PlanException('Plana bir ad ver.');
    final start = _day(startsOn);
    final end = _day(endsOn);
    if (end.isBefore(start)) throw const PlanException('Bitiş tarihi başlangıçtan önce olamaz.');
    return _repository.update(planId, title: t, startsOn: start, endsOn: end);
  }
}

class CreatePlan {
  CreatePlan(this._repository, this._ids, this._clock);

  final PlanRepository _repository;
  final IdGenerator _ids;
  final Clock _clock;

  /// Görevsiz plan da oluşturulabilir; görevler sonradan eklenir.
  Future<StudyPlan> call(NewPlanDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw const PlanException('Plana bir ad ver.');
    final start = _day(draft.startsOn);
    final end = _day(draft.endsOn);
    if (end.isBefore(start)) throw const PlanException('Bitiş tarihi başlangıçtan önce olamaz.');

    final planId = _ids.next();
    final plan = StudyPlan(
      id: planId,
      title: title,
      startsOn: start,
      endsOn: end,
      createdAt: _clock(),
      tasks: [for (final t in draft.tasks) _task(planId, t)],
    );
    await _repository.create(plan);
    return plan;
  }

  PlanTask _task(String planId, NewPlanTaskDraft t) => PlanTask(
        id: _ids.next(),
        planId: planId,
        title: t.title,
        bookId: t.bookId,
        contentNodeId: t.contentNodeId,
        targetQuestions: t.targetQuestions,
      );
}

/// Var olan plana görev ekler (haftalık plan büyüdükçe).
class AddPlanTasks {
  AddPlanTasks(this._repository, this._ids);

  final PlanRepository _repository;
  final IdGenerator _ids;

  Future<void> call(String planId, List<NewPlanTaskDraft> drafts) {
    final tasks = [
      for (final t in drafts)
        if (t.title.trim().isNotEmpty)
          PlanTask(
            id: _ids.next(),
            planId: planId,
            title: t.title.trim(),
            bookId: t.bookId,
            contentNodeId: t.contentNodeId,
            targetQuestions: t.targetQuestions,
          ),
    ];
    if (tasks.isEmpty) return Future.value();
    return _repository.addTasks(planId, tasks);
  }
}
