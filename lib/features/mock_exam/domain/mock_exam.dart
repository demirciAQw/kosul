import '../../../core/utils/id_generator.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../curriculum/domain/yks.dart';
import '../../question_bank/domain/question_card.dart';

enum MockKind {
  tyt('TYT'),
  ayt('AYT'),
  ydt('YDT'),
  branch('Branş');

  const MockKind(this.label);
  final String label;
}

/// YKS neti: 4 yanlış 1 doğruyu götürür.
double netOf(int correct, int wrong) => correct - wrong / 4;

class MockSection {
  const MockSection({
    required this.id,
    required this.subject,
    required this.questionCount,
    required this.correct,
    required this.wrong,
    required this.blank,
  });

  final String id;
  final String subject; // "TYT Matematik"
  final int questionCount;
  final int correct;
  final int wrong;
  final int blank;

  double get net => netOf(correct, wrong);
  String get name => subjectName(subject);
  String? get group => Yks.byKey(subject)?.group;
}

class MockExam {
  const MockExam({
    required this.id,
    required this.title,
    required this.kind,
    required this.takenOn,
    required this.createdAt,
    required this.sections,
    this.durationMinutes,
    this.note,
  });

  final String id;
  final String title;
  final MockKind kind;
  final DateTime takenOn;
  final DateTime createdAt;
  final List<MockSection> sections;
  final int? durationMinutes;
  final String? note;

  int get questionCount => sections.fold(0, (sum, s) => sum + s.questionCount);
  int get correct => sections.fold(0, (sum, s) => sum + s.correct);
  int get wrong => sections.fold(0, (sum, s) => sum + s.wrong);
  int get blank => sections.fold(0, (sum, s) => sum + s.blank);
  double get net => netOf(correct, wrong);

  MockSection? section(String subject) {
    for (final s in sections) {
      if (s.subject == subject) return s;
    }
    return null;
  }

  /// Soru başına ortalama süre (saniye); süre girilmediyse null.
  double? get secondsPerQuestion {
    final minutes = durationMinutes;
    if (minutes == null || questionCount == 0) return null;
    return minutes * 60 / questionCount;
  }
}

class MockSectionDraft {
  const MockSectionDraft({
    required this.subject,
    required this.questionCount,
    this.correct = 0,
    this.wrong = 0,
    this.blank = 0,
  });

  final String subject;
  final int questionCount;
  final int correct;
  final int wrong;
  final int blank;
}

class MockExamDraft {
  const MockExamDraft({
    required this.title,
    required this.kind,
    required this.takenOn,
    required this.sections,
    this.id,
    this.durationMinutes,
    this.note,
  });

  /// Doluysa var olan deneme güncellenir.
  final String? id;
  final String title;
  final MockKind kind;
  final DateTime takenOn;
  final int? durationMinutes;
  final String? note;
  final List<MockSectionDraft> sections;
}

class MockExamException implements Exception {
  const MockExamException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class MockExamRepository {
  Stream<List<MockExam>> watchAll(); // en yeni deneme başta
  Stream<MockExam?> watchById(String id);
  Future<MockExam?> findById(String id);

  /// Denemeyi ve tüm bölümlerini atomik olarak yazar (bölümler yenilenir).
  Future<void> save(MockExam exam);
  Future<void> updateSection(String sectionId, {required int correct, required int wrong, required int blank});

  /// Denemeyi siler. Ona bağlı fotoğrafsız hızlı kartlar da silinir;
  /// emek verilmiş kartlar defterde kalır.
  Future<void> delete(String id);
}

class SaveMockExam {
  SaveMockExam(this._repository, this._ids, this._clock);

  final MockExamRepository _repository;
  final IdGenerator _ids;
  final Clock _clock;

  Future<MockExam> call(MockExamDraft draft) async {
    if (draft.sections.isEmpty) throw const MockExamException('En az bir ders ekle.');
    for (final s in draft.sections) {
      final name = subjectName(s.subject);
      if (s.questionCount < 1) throw MockExamException('$name: soru sayısı en az 1 olmalı.');
      if (s.correct < 0 || s.wrong < 0 || s.blank < 0) {
        throw MockExamException('$name: sayılar negatif olamaz.');
      }
      if (s.correct + s.wrong + s.blank > s.questionCount) {
        throw MockExamException('$name: doğru, yanlış ve boşun toplamı ${s.questionCount} soruyu geçemez.');
      }
    }
    final existing = draft.id == null ? null : await _repository.findById(draft.id!);
    final title = draft.title.trim();
    final note = draft.note?.trim();
    final minutes = draft.durationMinutes;
    final exam = MockExam(
      id: draft.id ?? _ids.next(),
      title: title.isEmpty ? '${draft.kind.label} denemesi' : title,
      kind: draft.kind,
      takenOn: DateTime(draft.takenOn.year, draft.takenOn.month, draft.takenOn.day),
      createdAt: existing?.createdAt ?? _clock(),
      durationMinutes: (minutes != null && minutes > 0) ? minutes : null,
      note: (note == null || note.isEmpty) ? null : note,
      sections: [
        for (final s in draft.sections)
          MockSection(
            id: _ids.next(),
            subject: s.subject,
            questionCount: s.questionCount,
            correct: s.correct,
            wrong: s.wrong,
            blank: s.blank,
          ),
      ],
    );
    await _repository.save(exam);
    return exam;
  }
}

/// Deneme türüne göre hazır ders listesi (ÖSYM soru sayılarıyla).
List<MockSectionDraft> presetSections(MockKind kind, {String aytField = 'Sayısal'}) {
  switch (kind) {
    case MockKind.tyt:
      return [for (final s in Yks.tyt) MockSectionDraft(subject: s.key, questionCount: s.questions)];
    case MockKind.ayt:
      final names = Yks.aytFields[aytField] ?? Yks.aytFields['Sayısal']!;
      return [
        for (final s in Yks.ayt)
          if (names.contains(s.name)) MockSectionDraft(subject: s.key, questionCount: s.questions),
      ];
    case MockKind.ydt:
      return [for (final s in Yks.ydt) MockSectionDraft(subject: s.key, questionCount: s.questions)];
    case MockKind.branch:
      return const [];
  }
}

// ───────────────────────── Analiz ─────────────────────────

/// Bir dersin denemeler boyunca net seyri.
class SubjectNetStat {
  const SubjectNetStat({
    required this.subject,
    required this.last,
    required this.average,
    required this.best,
    required this.count,
    this.previous,
  });

  final String subject;
  final double last;
  final double? previous;
  final double average;
  final double best;
  final int count;

  String get name => subjectName(subject);
  double? get change {
    final p = previous;
    return p == null ? null : last - p;
  }
}

/// [exams] en yeniden eskiye sıralı olmalı (repository sırası).
List<SubjectNetStat> subjectNetStats(List<MockExam> exams) {
  final order = <String>[];
  final nets = <String, List<double>>{}; // en yeniden eskiye
  for (final exam in exams) {
    for (final s in exam.sections) {
      if (!nets.containsKey(s.subject)) order.add(s.subject);
      (nets[s.subject] ??= []).add(s.net);
    }
  }
  final out = <SubjectNetStat>[];
  for (final subject in order) {
    final list = nets[subject]!;
    final sum = list.fold<double>(0, (a, b) => a + b);
    out.add(SubjectNetStat(
      subject: subject,
      last: list.first,
      previous: list.length > 1 ? list[1] : null,
      average: sum / list.length,
      best: list.reduce((a, b) => a > b ? a : b),
      count: list.length,
    ));
  }
  return out;
}

/// Konu bazlı net kaybı: her yanlış 1,25 net (kaçan doğru + ceza), her boş 1 net.
class TopicLoss {
  const TopicLoss({
    required this.label,
    required this.wrong,
    required this.blank,
    this.sublabel,
    this.mebNodeId,
  });

  final String label;
  final String? sublabel;
  final String? mebNodeId; // null = konu girilmemiş
  final int wrong;
  final int blank;

  double get netLoss => wrong * 1.25 + blank;
}

const untaggedTopicLabel = 'Konusu girilmemiş';

/// Kartlardan konu bazlı net kaybı; en çok kaybettirenden başlayarak.
/// Konusu girilmemiş kartlar tek satırda, en sonda toplanır.
List<TopicLoss> topicNetLoss(Iterable<QuestionCard> cards, Map<String, CurriculumNode> curriculum) {
  const untagged = '';
  final wrong = <String, int>{};
  final blank = <String, int>{};
  for (final c in cards) {
    if (c.status == QuestionStatus.correct) continue;
    final id = c.mebNodeId;
    final key = (id != null && curriculum.containsKey(id)) ? id : untagged;
    if (c.status == QuestionStatus.wrong) {
      wrong[key] = (wrong[key] ?? 0) + 1;
    } else {
      blank[key] = (blank[key] ?? 0) + 1;
    }
  }
  final keys = {...wrong.keys, ...blank.keys};
  final out = <TopicLoss>[
    for (final k in keys)
      if (k != untagged)
        TopicLoss(
          label: curriculum[k]!.title,
          sublabel: curriculum[k]!.subjectLabel,
          mebNodeId: k,
          wrong: wrong[k] ?? 0,
          blank: blank[k] ?? 0,
        ),
  ]..sort((a, b) => b.netLoss.compareTo(a.netLoss));
  if (keys.contains(untagged)) {
    out.add(TopicLoss(label: untaggedTopicLabel, wrong: wrong[untagged] ?? 0, blank: blank[untagged] ?? 0));
  }
  return out;
}
