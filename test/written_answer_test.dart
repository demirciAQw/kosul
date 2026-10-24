import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/core/media/media_storage.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/question_bank/data/question_card_repository_impl.dart';
import 'package:kocum/features/question_bank/domain/question_bank.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';

class _SeqIds implements IdGenerator {
  var _n = 0;
  @override
  String next() => 'w${_n++}';
}

class _NoMedia implements MediaStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  test('yazılı cevap metin olarak saklanır ve tırnakla gösterilir', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftQuestionCardRepository(db);
    final save = SaveQuestionCard(repository: repo, media: _NoMedia(), ids: _SeqIds(), clock: () => DateTime(2026));

    final card = await save(const QuestionDraft(
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.independent,
      sourceName: 'Sınav',
      subject: 'AYT Matematik',
      writtenAnswer: true,
      correctAnswer: '  x = 3  ',
      givenAnswer: 'x = -3',
    ));
    expect(card.correctAnswer, 'x = 3');
    expect(card.givenAnswer, 'x = -3');
    expect(card.hasWrittenAnswer, isTrue);
    expect(card.answerText, 'Doğru cevap: "x = 3", senin cevabın: "x = -3"');

    // Düzenleme formu yazılı modda açılır.
    final stored = (await repo.findById(card.id))!;
    expect(QuestionDraft.fromCard(stored).writtenAnswer, isTrue);
  });

  test('şıklı cevap eski biçimde kalır', () {
    final c = QuestionCard(
      id: 'c',
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.book,
      sourceName: 'K',
      subject: 'TYT Fizik',
      difficulty: 5,
      createdAt: DateTime(2026),
      correctAnswer: 'C',
      givenAnswer: 'B',
    );
    expect(c.hasWrittenAnswer, isFalse);
    expect(c.answerText, 'Doğru cevap C, senin cevabın B');
  });
}
