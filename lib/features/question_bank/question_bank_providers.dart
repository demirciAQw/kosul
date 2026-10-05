import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../curriculum/curriculum_providers.dart';
import '../curriculum/domain/curriculum.dart';
import '../library/domain/library.dart';
import '../library/library_providers.dart';
import 'data/question_card_repository_impl.dart';
import 'domain/question_bank.dart';
import 'domain/question_card.dart';
import 'domain/question_grouping.dart';

final questionCardRepositoryProvider = Provider<QuestionCardRepository>(
    (ref) => DriftQuestionCardRepository(ref.watch(appDatabaseProvider)));

final saveQuestionCardProvider = Provider((ref) => SaveQuestionCard(
      repository: ref.watch(questionCardRepositoryProvider),
      media: ref.watch(mediaStorageProvider),
      ids: ref.watch(idGeneratorProvider),
      clock: ref.watch(clockProvider),
    ));

final deleteQuestionCardProvider = Provider((ref) => DeleteQuestionCard(
      repository: ref.watch(questionCardRepositoryProvider),
      media: ref.watch(mediaStorageProvider),
    ));

final gradeReviewProvider = Provider((ref) => GradeReview(
      repository: ref.watch(questionCardRepositoryProvider),
      clock: ref.watch(clockProvider),
    ));

// ───────────────────────── Defter: filtre + gruplama ─────────────────────────

class QuestionFilterNotifier extends Notifier<QuestionFilter> {
  @override
  QuestionFilter build() => const QuestionFilter();

  void setText(String? value) {
    final trimmed = value?.trim();
    state = state.copyWith(text: () => (trimmed == null || trimmed.isEmpty) ? null : trimmed);
  }

  void setStarredOnly(bool value) => state = state.copyWith(starredOnly: value);
  void apply(QuestionFilter filter) => state = filter;
  void reset() => state = const QuestionFilter();
}

final questionFilterProvider =
    NotifierProvider<QuestionFilterNotifier, QuestionFilter>(QuestionFilterNotifier.new);

class GroupByNotifier extends Notifier<GroupBy> {
  @override
  GroupBy build() => GroupBy.subject;
  void set(GroupBy value) => state = value;
}

final questionGroupByProvider = NotifierProvider<GroupByNotifier, GroupBy>(GroupByNotifier.new);

final filteredQuestionsProvider = StreamProvider<List<QuestionCard>>((ref) =>
    ref.watch(questionCardRepositoryProvider).watch(ref.watch(questionFilterProvider)));

final questionGroupsProvider = Provider<AsyncValue<List<QuestionGroup>>>((ref) {
  final cards = ref.watch(filteredQuestionsProvider);
  final by = ref.watch(questionGroupByProvider);
  final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
  final books = ref.watch(libraryProvider).value ?? const <Book>[];
  return cards.whenData((list) => groupQuestions(
        list,
        by,
        curriculum: {for (final n in curriculum) n.id: n},
        bookTitles: {for (final b in books) b.id: b.title},
      ));
});

final questionByIdProvider = StreamProvider.family<QuestionCard?, String>(
    (ref, id) => ref.watch(questionCardRepositoryProvider).watchById(id));

// ───────────────────────── Aralıklı tekrar ─────────────────────────

final dueCountProvider = StreamProvider<int>(
    (ref) => ref.watch(questionCardRepositoryProvider).watchDueCount(ref.watch(clockProvider)()));

/// Oturum başında bir kez okunur; tekrar sırasında liste kaymasın diye canlı akış değildir.
final dueReviewsProvider = FutureProvider.autoDispose<List<DueReview>>(
    (ref) => ref.watch(questionCardRepositoryProvider).dueNow(ref.watch(clockProvider)()));
