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
import 'domain/quick_mark.dart';
import 'domain/smart_search.dart';
import 'data/search_store.dart';
import '../settings/settings_providers.dart';
import '../curriculum/domain/yks.dart';
import '../../core/text/turkish_text.dart';
import '../ocr/ocr_providers.dart';
import '../ocr/domain/ocr.dart';
import '../ocr/auto_tag_providers.dart';
import 'similar_providers.dart';

final questionCardRepositoryProvider = Provider<QuestionCardRepository>(
    (ref) => DriftQuestionCardRepository(ref.watch(appDatabaseProvider)));

final saveQuestionCardProvider = Provider((ref) => SaveQuestionCard(
      repository: ref.watch(questionCardRepositoryProvider),
      media: ref.watch(mediaStorageProvider),
      ids: ref.watch(idGeneratorProvider),
      clock: ref.watch(clockProvider),
    ));

final updateQuestionCardProvider = Provider((ref) => UpdateQuestionCard(
      repository: ref.watch(questionCardRepositoryProvider),
      media: ref.watch(mediaStorageProvider),
      clock: ref.watch(clockProvider),
    ));

final quickMarkProvider = Provider((ref) => QuickMarkQuestions(
      repository: ref.watch(questionCardRepositoryProvider),
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

/// Akıllı arama açık mı (Ayarlar › Arama).
final smartSearchEnabledProvider = Provider<bool>((ref) => ref.watch(settingsProvider).value?.smartSearch ?? true);

bool _smartActive(Ref ref) =>
    ref.watch(smartSearchEnabledProvider) && (ref.watch(questionFilterProvider).text?.trim().isNotEmpty ?? false);

/// Veritabanı sonucu: akıllı aramada metin süzgeci veritabanında değil
/// [smartSearchResultProvider]'da uygulanır (öteki filtreler burada).
final _searchBaseProvider = StreamProvider<List<QuestionCard>>((ref) {
  final filter = ref.watch(questionFilterProvider);
  final repo = ref.watch(questionCardRepositoryProvider);
  return repo.watch(_smartActive(ref) ? filter.copyWith(text: () => null) : filter);
});

/// Akıllı arama sonucu (puanlar ve "bunu mu demek istedin"); arama yoksa null.
final smartSearchResultProvider = Provider<AsyncValue<SmartSearchResult?>>((ref) {
  final base = ref.watch(_searchBaseProvider);
  if (!_smartActive(ref)) return base.whenData<SmartSearchResult?>((_) => null);
  final text = ref.watch(questionFilterProvider).text!;
  final curriculum = {for (final n in ref.watch(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n};
  // Fotoğraftan okunan soru metni (kök ve şıklar) de aranır.
  final ocr = ref.watch(ocrRecordsProvider).value ?? const <String, OcrRecord>{};
  final tags = ref.watch(autoTagsProvider);
  return base.whenData((cards) => smartSearch(cards, text, (c) {
        final read = ocr[OcrJob.questionId(c.id)];
        final node = c.mebNodeId == null ? null : curriculum[c.mebNodeId];
        final topic = node?.title ?? (c.topicText == null ? null : titleCaseTr(c.topicText!));
        return [
          if (topic != null) SearchField(topic, fieldWeights.topic),
          SearchField(subjectName(c.subject), fieldWeights.subject),
          SearchField(c.sourceName, fieldWeights.source),
          if (c.testLabel != null) SearchField(c.testLabel!, fieldWeights.test),
          if (c.reasonText != null) SearchField(c.reasonText!, fieldWeights.reason),
          if (c.note != null) SearchField(c.note!, fieldWeights.note),
          SearchField(c.status.label, fieldWeights.status),
          // Okunan metin parçalarıyla: soru cümlesi (biraz daha ağır), paragraf /
          // verilen bilgi (grafik açıklamaları dahil), şıklar, öncüller.
          if (read != null && read.ok)
            ...() {
              final parts = questionPartsOf(read);
              return [
                if (parts.prompt.isNotEmpty) SearchField(parts.prompt, fieldWeights.ocr + 0.1),
                if (parts.passage.isNotEmpty) SearchField(parts.passage, fieldWeights.ocr),
                if (parts.options.isNotEmpty) SearchField(parts.options, fieldWeights.ocr),
                if (parts.given.isNotEmpty) SearchField(parts.given, fieldWeights.ocr),
              ];
            }(),
          // Otomatik konu ve soru türü ("grafik yorumlama", "paragraf" …).
          if (tags[c.id] != null) SearchField(tags[c.id]!.summary, fieldWeights.reason),
        ];
      }));
});

/// Defter'de gösterilen sorular: akıllı aramada alaka sırasıyla.
final filteredQuestionsProvider = Provider<AsyncValue<List<QuestionCard>>>((ref) {
  final smart = ref.watch(smartSearchResultProvider);
  final result = smart.value;
  if (result != null) return AsyncData(result.cards);
  return ref.watch(_searchBaseProvider);
});

final searchHistoryRepositoryProvider = Provider((ref) => SearchHistoryRepository(ref.watch(appDatabaseProvider)));
final searchLogProvider = Provider<SearchLog>((ref) => SearchLog());

/// Arama geçmişi: tarayıcıdaki gibi en yeni başta.
class SearchHistoryNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() => ref.watch(searchHistoryRepositoryProvider).load();

  Future<void> add(String query) async {
    final current = state.value ?? await future;
    state = AsyncData(await ref.read(searchHistoryRepositoryProvider).save(pushHistory(current, query)));
  }

  Future<void> remove(String query) async {
    final current = state.value ?? const <String>[];
    state = AsyncData(await ref.read(searchHistoryRepositoryProvider).save([for (final e in current) if (e != query) e]));
  }

  Future<void> clear() async => state = AsyncData(await ref.read(searchHistoryRepositoryProvider).save(const []));
}

final searchHistoryProvider = AsyncNotifierProvider<SearchHistoryNotifier, List<String>>(SearchHistoryNotifier.new);

/// Filtresiz bütün defter (dışa aktarma "Tüm defter" için).
final allQuestionsProvider = StreamProvider<List<QuestionCard>>(
    (ref) => ref.watch(questionCardRepositoryProvider).watch(const QuestionFilter()));

final questionGroupsProvider = Provider<AsyncValue<List<QuestionGroup>>>((ref) {
  final cards = ref.watch(filteredQuestionsProvider);
  final by = ref.watch(questionGroupByProvider);
  final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
  final books = ref.watch(libraryProvider).value ?? const <Book>[];
  final tags = ref.watch(autoTagsProvider);
  final similar = by == GroupBy.similar ? ref.watch(similarGroupsProvider) : const <String, int>{};
  return cards.whenData((list) => groupQuestions(
        list,
        by,
        curriculum: {for (final n in curriculum) n.id: n},
        bookTitles: {for (final b in books) b.id: b.title},
        fallbackTopics: fallbackTopicsFor(list, tags),
        similarGroups: by == GroupBy.similar ? similar : const {},
        similarTitles: by == GroupBy.similar ? similarTitlesFor(similar, list, fallbackTopicsFor(list, tags)) : const {},
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

// ───────────────────────── Eksikler ─────────────────────────

typedef IncompleteCard = ({QuestionCard card, List<MissingPart> missing});

final _incompleteRawProvider = StreamProvider<List<QuestionCard>>(
    (ref) => ref.watch(questionCardRepositoryProvider).watchIncomplete());

/// Fotoğrafı, çözümü, nedeni ya da konusu eksik kartlar. Konu yalnızca o dersin
/// müfredatında konu listesi varsa eksik sayılır.
final incompleteQuestionsProvider = Provider<AsyncValue<List<IncompleteCard>>>((ref) {
  final raw = ref.watch(_incompleteRawProvider);
  final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
  final withTopics = {for (final n in curriculum) n.subjectLabel};
  return raw.whenData((cards) {
    final out = <IncompleteCard>[];
    for (final c in cards) {
      final missing = c.missingParts(topicAvailable: withTopics.contains(c.subject));
      if (missing.isNotEmpty) out.add((card: c, missing: missing));
    }
    return out;
  });
});

final incompleteCountProvider =
    Provider<int>((ref) => ref.watch(incompleteQuestionsProvider).value?.length ?? 0);

/// Denemelerden gelen yanlış ve boşlar (deneme analizinde konu bazlı net kaybı).
final mockExamMistakesProvider = StreamProvider<List<QuestionCard>>(
    (ref) => ref.watch(questionCardRepositoryProvider).watchMockExamMistakes());

/// Bir kitap testine bağlı kartlar (test ekranı).
final cardsForNodeProvider = StreamProvider.family<List<QuestionCard>, String>(
    (ref, nodeId) => ref.watch(questionCardRepositoryProvider).watchForNode(nodeId));

/// Defter'de çoklu seçim (uzun bas → seç → sil).
class QuestionSelection extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) => state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
  void clear() => state = const {};
  void selectAll(Iterable<String> ids) => state = {...state, ...ids};
}

final questionSelectionProvider = NotifierProvider<QuestionSelection, Set<String>>(QuestionSelection.new);

/// Defter görünümü: galeri (ızgara) ya da gruplu liste.
class NotebookGalleryMode extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool gallery) => state = gallery;
}

final notebookGalleryProvider = NotifierProvider<NotebookGalleryMode, bool>(NotebookGalleryMode.new);

/// Benzer grupların başlığı: gruptaki soruların en sık konusu, yoksa "Benzer sorular N".
Map<int, String> similarTitlesFor(Map<String, int> groups, List<QuestionCard> cards, Map<String, String> topics) {
  final counts = <int, Map<String, int>>{};
  for (final c in cards) {
    final g = groups[c.id];
    final t = topics[c.id];
    if (g == null || t == null) continue;
    final m = counts[g] ??= {};
    m[t] = (m[t] ?? 0) + 1;
  }
  final out = <int, String>{};
  for (final g in groups.values.toSet()) {
    final m = counts[g];
    final top = m == null ? null : (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    out[g] = top == null ? 'Benzer sorular $g' : '$top · benzer $g';
  }
  return out;
}
