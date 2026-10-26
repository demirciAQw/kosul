import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../../core/utils/enum_x.dart';
import '../curriculum/curriculum_providers.dart';
import '../curriculum/domain/curriculum.dart';
import '../question_bank/domain/question_card.dart';
import '../question_bank/question_bank_providers.dart';
import 'data/dashboard_repository_impl.dart';
import 'domain/dashboard.dart';
import 'domain/patterns.dart';
import 'domain/observations.dart';
import 'domain/deep_analysis.dart';
import '../study_session/study_session_providers.dart';
import '../study_session/domain/study_session.dart';
import '../mock_exam/mock_exam_providers.dart';
import '../library/library_providers.dart';
import '../ocr/ocr_providers.dart';
import '../ocr/domain/ocr.dart';
import 'domain/stem_analysis.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
    (ref) => DriftDashboardRepository(ref.watch(appDatabaseProvider)));

class DimensionNotifier extends Notifier<MistakeDimension> {
  @override
  MistakeDimension build() => MistakeDimension.topic;
  void set(MistakeDimension value) => state = value;
}

final dashboardDimensionProvider =
    NotifierProvider<DimensionNotifier, MistakeDimension>(DimensionNotifier.new);

/// Gün sayısı; 0 = tüm zamanlar.
class RangeNotifier extends Notifier<int> {
  @override
  int build() => 30;
  void set(int days) => state = days;
}

final dashboardRangeProvider = NotifierProvider<RangeNotifier, int>(RangeNotifier.new);

final mistakeStatsProvider = StreamProvider<List<LabeledStat>>((ref) {
  final by = ref.watch(dashboardDimensionProvider);
  final days = ref.watch(dashboardRangeProvider);
  final now = ref.watch(clockProvider)();
  final curriculum = {for (final n in ref.watch(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n};
  final since = days == 0 ? null : DateTime(now.year, now.month, now.day - days + 1);

  return ref.watch(dashboardRepositoryProvider).watchMistakeStats(by, since: since).map((stats) => [
        for (final s in stats)
          switch (by) {
            MistakeDimension.topic => LabeledStat(
                label: curriculum[s.key]?.title ?? 'Konu belirtilmemiş',
                sublabel: curriculum[s.key]?.subjectLabel,
                count: s.count,
                lostSeconds: s.lostSeconds,
              ),
            MistakeDimension.reason => LabeledStat(
                label: MistakeReason.values.byNameOrNull(s.key)?.label ?? 'Neden belirtilmemiş',
                count: s.count,
                lostSeconds: s.lostSeconds,
              ),
            MistakeDimension.subject => LabeledStat(
                label: s.key ?? 'Ders belirtilmemiş',
                count: s.count,
                lostSeconds: s.lostSeconds,
              ),
          },
      ]);
});

final dailyStudyProvider = StreamProvider<List<DailyStudy>>((ref) =>
    ref.watch(dashboardRepositoryProvider).watchDailyStudy(days: 7, today: ref.watch(clockProvider)()));

final _mistakeCardsProvider = StreamProvider<List<QuestionCard>>((ref) => ref
    .watch(questionCardRepositoryProvider)
    .watch(const QuestionFilter(statuses: {QuestionStatus.wrong, QuestionStatus.blank})));

/// Seçili zaman aralığında ders bazlı hata örüntüleri.
final subjectPatternsProvider = Provider<AsyncValue<List<SubjectPattern>>>((ref) {
  final cards = ref.watch(_mistakeCardsProvider);
  final days = ref.watch(dashboardRangeProvider);
  final now = ref.watch(clockProvider)();
  final since = days == 0 ? null : DateTime(now.year, now.month, now.day - days + 1);
  final curriculum = {for (final n in ref.watch(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n};
  return cards.whenData((list) => findSubjectPatterns(
        since == null ? list : list.where((c) => !c.createdAt.isBefore(since)),
        curriculum,
      ));
});

/// Analiz için geniş oturum geçmişi (Geçmiş ekranındaki sınırdan bağımsız).
final _analysisSessionsProvider = StreamProvider<List<StudySession>>(
    (ref) => ref.watch(studySessionRepositoryProvider).watchHistory(limit: 3000));

/// Derin analiz: koşulları sabit tutarak karşılaştırmalı bulgular.
final deepAnalysisProvider = Provider<AsyncValue<DeepAnalysis>>((ref) {
  final sessions = ref.watch(_analysisSessionsProvider);
  final results = ref.watch(testResultsProvider);
  final exams = ref.watch(mockExamsProvider);
  final books = ref.watch(libraryProvider);
  if (sessions.isLoading || results.isLoading || exams.isLoading || books.isLoading) {
    return const AsyncLoading();
  }
  final error = [sessions, results, exams, books].where((a) => a.hasError).firstOrNull;
  if (error != null) return AsyncError(error.error!, error.stackTrace ?? StackTrace.empty);
  return AsyncData(analyze(buildObservations(
    sessions: sessions.value ?? const [],
    results: results.value ?? const {},
    exams: exams.value ?? const [],
    books: books.value ?? const [],
  )));
});

/// Okuma kaydından asıl sorunun soru cümlesi (kökü) ve öncüllü olup olmadığı.
/// Eski kayıtlarda kökün son "?"li satırı.
({String prompt, bool hasStatements})? questionPromptOf(OcrRecord r) {
  final questions = r.structure?['questions'];
  final primary = r.structure?['primary'];
  if (questions is List && primary is int && primary >= 0 && primary < questions.length) {
    final q = questions[primary];
    if (q is Map) {
      final prompt = (q['prompt'] as String?)?.trim() ?? '';
      final statements = q['statements'];
      if (prompt.isNotEmpty) return (prompt: prompt, hasStatements: statements is List && statements.isNotEmpty);
    }
  }
  final lines = (r.parsed?.stem ?? '').split('\n').where((l) => l.contains('?')).toList();
  return lines.isEmpty ? null : (prompt: lines.last.trim(), hasStatements: false);
}

/// Soru kökü analizi: okunmuş soru cümleleri + kartın durumu ve hata nedeni.
final stemReportProvider = Provider<StemReport?>((ref) {
  final cards = ref.watch(allQuestionsProvider).value;
  final records = ref.watch(ocrRecordsProvider).value;
  if (cards == null || records == null) return null;
  final samples = <StemSample>[];
  for (final c in cards) {
    final r = records[OcrJob.questionId(c.id)];
    if (r == null || !r.ok || r.imagePath != c.questionImage) continue;
    final p = questionPromptOf(r);
    if (p == null) continue;
    samples.add(StemSample(
      prompt: p.prompt,
      hasStatements: p.hasStatements,
      status: c.status,
      reason: c.reason,
      subject: c.subject,
    ));
  }
  return analyzeStems(samples);
});
