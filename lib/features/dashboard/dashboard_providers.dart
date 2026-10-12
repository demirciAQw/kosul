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
