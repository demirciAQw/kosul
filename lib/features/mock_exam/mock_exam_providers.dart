import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../question_bank/question_bank_providers.dart';
import 'data/mock_exam_repository_impl.dart';
import 'domain/karne_import.dart';
import 'domain/mock_exam.dart';

final mockExamRepositoryProvider =
    Provider<MockExamRepository>((ref) => DriftMockExamRepository(ref.watch(appDatabaseProvider)));

final saveMockExamProvider = Provider((ref) => SaveMockExam(
      ref.watch(mockExamRepositoryProvider),
      ref.watch(idGeneratorProvider),
      ref.watch(clockProvider),
    ));

final mockExamsProvider = StreamProvider<List<MockExam>>((ref) => ref.watch(mockExamRepositoryProvider).watchAll());

final mockExamByIdProvider = StreamProvider.family<MockExam?, String>(
    (ref, id) => ref.watch(mockExamRepositoryProvider).watchById(id));

/// Deneme sekmesinde seçili tür (TYT / AYT / YDT / Branş).
class MockKindNotifier extends Notifier<MockKind> {
  @override
  MockKind build() => MockKind.tyt;
  void set(MockKind value) => state = value;
}

final mockKindFilterProvider = NotifierProvider<MockKindNotifier, MockKind>(MockKindNotifier.new);

final importKarneProvider = Provider((ref) => ImportKarne(
      save: ref.watch(saveMockExamProvider),
      exams: ref.watch(mockExamRepositoryProvider),
      cards: ref.watch(questionCardRepositoryProvider),
      ids: ref.watch(idGeneratorProvider),
      clock: ref.watch(clockProvider),
    ));
