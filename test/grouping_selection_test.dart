import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/curriculum/domain/curriculum.dart';
import 'package:kocum/features/library/domain/library.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/domain/question_grouping.dart';
import 'package:kocum/features/study_session/presentation/tree_selection.dart';

CurriculumNode _node(String id, String title, {String? parent, int depth = 0}) => CurriculumNode(
      id: id,
      parentId: parent,
      examType: 'TYT',
      subject: 'Matematik',
      title: title,
      depth: depth,
      sortOrder: 0,
    );

QuestionCard _card(String id, {String? meb, String subject = 'TYT Matematik', String? bookId}) => QuestionCard(
      id: id,
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.book,
      questionImage: 'q/$id.webp',
      solutionText: 'çözüm',
      sourceName: 'Kaynak',
      subject: subject,
      difficulty: 5,
      createdAt: DateTime(2026, 10, 5),
      mebNodeId: meb,
      bookId: bookId,
    );

void main() {
  group('Soru gruplama', () {
    final curriculum = {
      'prob': _node('prob', 'Problemler'),
      'yas': _node('yas', 'Yaş Problemleri', parent: 'prob', depth: 1),
    };

    test('ders modu: Ders › Konu', () {
      final groups = groupQuestions(
        [_card('1', meb: 'yas'), _card('2', meb: 'yas'), _card('3')],
        GroupBy.subject,
        curriculum: curriculum,
        bookTitles: const {},
      );
      expect(groups, hasLength(1));
      expect(groups.single.total, 3);
      // "Konu belirtilmemiş" her zaman sona düşer.
      expect(groups.single.children.last.title, noTopicTitle);
    });

    test('konu modu: alt konu ana konunun altına yerleşir', () {
      final groups = groupQuestions(
        [_card('1', meb: 'yas'), _card('2', meb: 'prob')],
        GroupBy.topic,
        curriculum: curriculum,
        bookTitles: const {},
      );
      expect(groups.single.title, 'Problemler');
      expect(groups.single.cards, hasLength(1));
      expect(groups.single.children.single.title, 'Yaş Problemleri');
    });

    test('kitap modu: kitap adı, kitap silinmişse kaynak adı', () {
      final groups = groupQuestions(
        [_card('1', bookId: 'b1'), _card('2')],
        GroupBy.book,
        curriculum: curriculum,
        bookTitles: const {'b1': '345 TYT Mat'},
      );
      expect(groups.map((g) => g.title), containsAll(['345 TYT Mat', 'Kaynak']));
    });

    test('alt konu kimlikleri', () {
      expect(descendantIds(curriculum.values, 'prob'), {'prob', 'yas'});
      expect(descendantIds(curriculum.values, 'yas'), {'yas'});
    });
  });

  group('Çoklu seçim ağacı', () {
    final book = Book(
      id: 'b',
      title: 'Kitap',
      examType: 'TYT',
      subject: 'Matematik',
      pageCount: 20,
      avgQuestionsPerPage: 5,
      createdAt: DateTime(2026, 10, 5),
      roots: const [
        ContentNode(id: 'u1', level: NodeLevel.unit, title: 'Ünite 1', children: [
          ContentNode(id: 'k1', level: NodeLevel.topic, title: 'Konu A', pageStart: 1, pageEnd: 4),
          ContentNode(id: 'k2', level: NodeLevel.topic, title: 'Konu B', pageStart: 5, pageEnd: 8),
        ]),
      ],
    );

    test('ünite seçmek tek blok üretir', () {
      final roots = [SelectableNode.fromBook(book)];
      final unit = roots.single.children.single;
      final selection = TreeSelection.empty.setNode(unit, selected: true);
      final drafts = selection.toDrafts(roots, selection.computeStates(roots));
      expect(drafts, hasLength(1));
      expect(drafts.single.pages, [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(drafts.single.estimatedQuestions, 40);
    });

    test('tek sayfa seçmek kısmi durum verir', () {
      final roots = [SelectableNode.fromBook(book)];
      final leaf = roots.single.children.single.children.first;
      final selection = TreeSelection.empty.togglePage(leaf, 2);
      final states = selection.computeStates(roots);
      expect(states[leaf.id], CheckState.partial);
      expect(states[roots.single.id], CheckState.partial);
      final drafts = selection.toDrafts(roots, states);
      expect(drafts.single.pages, [2]);
    });
  });
}
