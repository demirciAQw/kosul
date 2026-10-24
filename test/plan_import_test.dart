import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/library/domain/library.dart';
import 'package:kocum/features/planning/domain/plan_import.dart';

Book _book() => Book(
      id: 'b1',
      title: 'MEB 11. Sınıf Matematik',
      publisher: 'MEB',
      examType: 'AYT',
      subject: 'Matematik',
      pageCount: 378,
      avgQuestionsPerPage: 3,
      createdAt: DateTime(2026),
      roots: [
        ContentNode(
          id: 'u4',
          level: NodeLevel.unit,
          title: '4. Tema: Nicelikler ve Değişimler (2)',
          pageStart: 244,
          pageEnd: 321,
          children: [
            ContentNode(
              id: 'k41',
              level: NodeLevel.topic,
              title: '4.1 Üstel Fonksiyonlar ve Nitel Özellikleri',
              pageStart: 248,
              pageEnd: 266,
              children: const [],
            ),
          ],
        ),
      ],
    );

void main() {
  const reply = '''
Harika, işte programın:

```json
{
  "format": "kocum.plan", "version": 1, "title": "26 Ekim haftası",
  "tasks": [
    {"date": "2026-10-27", "time": "19:00", "minutes": 40, "title": "Üstel fonksiyonlar tekrar",
     "book": "MEB 11. Sınıf Matematik", "section": "4.1 Üstel Fonksiyonlar ve Nitel Özellikleri",
     "pages": "248-266", "questions": 20},
    {"date": "2026-10-26", "title": "Deneme analizi", "book": "Olmayan Kitap"},
    {"date": "2026-10-26", "minutes": 30}
  ]
}
```
''';

  test('sohbet cevabından JSON bloğunu okur, eşler, sıralar', () {
    final r = parsePlanJson(reply, books: [_book()], today: DateTime(2026, 10, 25));
    expect(r.draft.title, '26 Ekim haftası');
    expect(r.draft.startsOn, DateTime(2026, 10, 26));
    expect(r.draft.endsOn, DateTime(2026, 10, 27));
    expect(r.draft.tasks, hasLength(2)); // başlıksız görev atlandı
    expect(r.draft.tasks.first.title, startsWith('Pzt 26.10 · Deneme analizi'));
    final t = r.draft.tasks.last;
    expect(t.title, startsWith('Sal 27.10 19:00 · Üstel fonksiyonlar tekrar'));
    expect(t.title, contains('s. 248-266'));
    expect(t.bookId, 'b1');
    expect(t.contentNodeId, 'k41');
    expect(t.targetQuestions, 20);
    expect(r.matchedBooks, 1);
    expect(r.warnings.join(' '), contains('Olmayan Kitap'));
    expect(r.warnings.join(' '), contains('başlığı yok'));
  });

  test('JSON yoksa açık hata', () {
    expect(() => parsePlanJson('program yok', books: const [], today: DateTime(2026)),
        throwsA(isA<PlanImportException>()));
    expect(() => parsePlanJson('{"tasks": []}', books: const [], today: DateTime(2026)),
        throwsA(isA<PlanImportException>()));
  });
}
