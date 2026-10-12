import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/utils/formatters.dart';
import 'package:kocum/features/curriculum/domain/curriculum.dart';
import 'package:kocum/features/curriculum/domain/yks.dart';
import 'package:kocum/features/dashboard/domain/patterns.dart';
import 'package:kocum/features/mock_exam/domain/mock_exam.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/presentation/screens/optic_form_screen.dart';
import 'package:kocum/features/study_session/domain/study_session.dart';

CurriculumNode _node(String id, String title, {String? parent, int depth = 0}) => CurriculumNode(
      id: id,
      parentId: parent,
      examType: 'TYT',
      subject: 'Matematik',
      title: title,
      depth: depth,
      sortOrder: 0,
    );

QuestionCard _card(
  String id, {
  QuestionStatus status = QuestionStatus.wrong,
  String? meb,
  MistakeReason? reason,
  String subject = 'TYT Matematik',
  String? image,
  String? solution,
  int? no,
}) =>
    QuestionCard(
      id: id,
      status: status,
      origin: QuestionOrigin.book,
      sourceName: 'Kaynak',
      subject: subject,
      difficulty: 5,
      createdAt: DateTime(2026, 10, 12),
      mebNodeId: meb,
      reason: reason,
      questionImage: image,
      solutionText: solution,
      questionNo: no,
    );

void main() {
  final curriculum = {
    'prob': _node('prob', 'Problemler'),
    'yas': _node('yas', 'Yaş Problemleri', parent: 'prob', depth: 1),
    'isci': _node('isci', 'İşçi Problemleri', parent: 'prob', depth: 1),
    'geo': _node('geo', 'Üçgenler'),
  };

  group('YKS yapısı', () {
    test('test toplamları ÖSYM ile aynı', () {
      int sum(List<ExamSubject> l) => l.fold(0, (a, s) => a + s.questions);
      expect(sum(Yks.tyt), 120);
      expect(sum(Yks.ayt), 160);
      expect(sum(Yks.ydt), 80);
    });
    test('ders anahtarı', () {
      expect(Yks.byKey('AYT Fizik')?.questions, 14);
      expect(subjectName('TYT Din Kültürü'), 'Din Kültürü');
    });
  });

  group('Net', () {
    test('4 yanlış 1 doğruyu götürür', () {
      expect(netOf(30, 8), 28);
      expect(formatNet(netOf(30, 7)), '28,25');
      expect(formatNet(-1.5), '-1,50');
      expect(formatNet(28), '28');
    });

    test('optik sonucu sayıları kendiliğinden hesaplar', () {
      const r = OpticFormResult(total: 16, marks: {3: QuestionStatus.wrong, 7: QuestionStatus.wrong, 9: QuestionStatus.blank});
      expect(r.correct, 13);
      expect(r.wrong, 2);
      expect(r.blank, 1);
      expect(r.net, 12.5);
    });

    test('hazır ders listeleri', () {
      expect(presetSections(MockKind.tyt), hasLength(9));
      expect(presetSections(MockKind.ayt, aytField: 'Eşit Ağırlık').map((s) => s.subject),
          ['AYT Matematik', 'AYT Edebiyat', 'AYT Tarih-1', 'AYT Coğrafya-1']);
    });
  });

  test('ders bazlı net seyri (en yeni başta)', () {
    MockExam exam(String id, int c, int w) => MockExam(
          id: id,
          title: id,
          kind: MockKind.tyt,
          takenOn: DateTime(2026, 10, 1),
          createdAt: DateTime(2026, 10, 1),
          sections: [
            MockSection(id: '$id-m', subject: 'TYT Matematik', questionCount: 40, correct: c, wrong: w, blank: 40 - c - w),
          ],
        );
    final stats = subjectNetStats([exam('yeni', 30, 4), exam('eski', 25, 8)]);
    expect(stats.single.last, 29);
    expect(stats.single.previous, 23);
    expect(stats.single.change, 6);
    expect(stats.single.average, 26);
  });

  test('konu bazlı net kaybı: yanlış 1,25, boş 1', () {
    final losses = topicNetLoss([
      _card('1', meb: 'yas'),
      _card('2', meb: 'yas', status: QuestionStatus.blank),
      _card('3', meb: 'geo'),
      _card('4'),
    ], curriculum);
    expect(losses.first.label, 'Yaş Problemleri');
    expect(losses.first.netLoss, 2.25);
    expect(losses.last.label, untaggedTopicLabel);
  });

  group('Eksikler', () {
    test('hızlı kart: fotoğraf, çözüm, neden ve konu eksik', () {
      final card = _card('1', no: 7);
      expect(card.missingParts(topicAvailable: true),
          [MissingPart.photo, MissingPart.solution, MissingPart.reason, MissingPart.topic]);
      expect(card.isBare, isTrue);
      expect(card.shortTitle, 'Soru 7');
    });
    test('müfredatı olmayan derste konu eksik sayılmaz', () {
      final card = _card('1', image: 'q.webp', solution: 'x', reason: MistakeReason.calculation, subject: 'TYT Fizik');
      expect(card.missingParts(topicAvailable: false), isEmpty);
    });
    test('taslak: yalnızca ders zorunlu', () {
      const draft = QuestionDraft(status: QuestionStatus.wrong, origin: QuestionOrigin.book, sourceName: '');
      expect(draft.validate(), [DraftIssue.missingSubject]);
    });
  });

  test('kitapsız blok: konu anlatımı soru istemez, test adı kitap adı içermez', () {
    const lecture = SessionItem(id: 'a', label: 'Konu çalışması: TYT Matematik', activity: StudyActivity.lecture);
    const book = SessionItem(id: 'b', label: '345 TYT Mat › Problemler › Yaş', bookId: 'k');
    expect(lecture.hasQuestions, isFalse);
    expect(book.hasQuestions, isTrue);
    expect(book.testLabel, 'Problemler › Yaş');
  });

  group('Örüntüler', () {
    test('konu ve neden yoğunlaşması yakalanır', () {
      final patterns = findSubjectPatterns([
        _card('1', meb: 'yas', reason: MistakeReason.calculation),
        _card('2', meb: 'yas', reason: MistakeReason.calculation),
        _card('3', meb: 'isci', reason: MistakeReason.calculation),
        _card('4', meb: 'geo', reason: MistakeReason.knowledgeGap),
      ], curriculum);
      expect(patterns, hasLength(1));
      final text = patterns.single.insights.join(' ');
      expect(text, contains('Problemler'));
      expect(text, contains('Yaş Problemleri'));
      expect(text, contains('işlem hatası'));
    });
    test('az veriyle yorum yapılmaz', () {
      expect(findSubjectPatterns([_card('1', meb: 'yas')], curriculum), isEmpty);
    });
  });
}
