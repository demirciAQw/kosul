import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/database/app_database.dart';
import 'package:kocum/features/question_bank/data/question_card_repository_impl.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/domain/srs.dart';

QuestionCard _card(String id) => QuestionCard(
      id: id,
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.independent,
      sourceName: 'K',
      subject: 'TYT Matematik',
      difficulty: 5,
      createdAt: DateTime(2026, 10, 13),
    );

void main() {
  test('kart silinince tekrar kaydı ve sayaç da gider', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftQuestionCardRepository(db);
    final now = DateTime(2026, 10, 13, 12);

    await repo.insert(_card('a'), review: ReviewState.initial(now));
    await repo.insert(_card('b'), review: ReviewState.initial(now));
    expect(await repo.dueNow(now.add(const Duration(days: 1))), hasLength(2));

    await repo.delete('a');

    expect(await repo.findById('a'), isNull);
    expect(await repo.reviewStateOf('a'), isNull);
    final due = await repo.dueNow(now.add(const Duration(days: 1)));
    expect(due.map((d) => d.card.id), ['b']);
    expect(await repo.watchDueCount(now.add(const Duration(days: 1))).first, 1);
  });
}
