import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/json/json_reader.dart';
import 'package:kocum/core/utils/formatters.dart';
import 'package:kocum/features/curriculum/domain/curriculum.dart';
import 'package:kocum/features/library/data/models/book_template_model.dart';
import 'package:kocum/features/question_bank/domain/srs.dart';

void main() {
  group('Kitap şablonu JSON', () {
    test('örnek şablon ayrıştırılır ve gidiş-dönüş kayıpsızdır', () {
      final raw = File('assets/templates/345_TYT_Mat.json').readAsStringSync();
      final model = BookTemplateModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final again = BookTemplateModel.fromJson(jsonDecode(jsonEncode(model.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(again.toJson()), jsonEncode(model.toJson()));
      expect(model.units, hasLength(3));
    });

    test('hatalı sayfa aralığı tam yoluyla raporlanır', () {
      final json = {
        'schemaVersion': 1,
        'book': {'title': 'X', 'examType': 'TYT', 'subject': 'Matematik', 'pageCount': 100, 'avgQuestionsPerPage': 5},
        'units': [
          {'title': 'A', 'pageStart': 50, 'pageEnd': 40},
        ],
      };
      expect(
        () => BookTemplateModel.fromJson(json),
        throwsA(isA<JsonFormatException>().having((e) => e.path, 'path', r'$.units[0].pageEnd')),
      );
    });

    test('daha yeni şema sürümü reddedilir', () {
      final json = {'schemaVersion': 99, 'book': {}, 'units': []};
      expect(() => BookTemplateModel.fromJson(json), throwsA(isA<JsonFormatException>()));
    });
  });

  test('Türkçe konu eşleştirme', () {
    CurriculumNode node(String id, String title) =>
        CurriculumNode(id: id, examType: 'TYT', subject: 'Matematik', title: title, depth: 1, sortOrder: 0);
    final matcher = TopicMatcher([node('yas', 'Yaş Problemleri'), node('isci', 'İşçi Problemleri')]);
    expect(matcher.match('YAŞ PROBLEMLERİ')?.nodeId, 'yas');
    expect(matcher.match('İşçi - Havuz Problemleri')?.nodeId, 'isci');
    expect(matcher.match('Trigonometri'), isNull);
  });

  group('SM-2', () {
    final t0 = DateTime(2026, 10, 5, 10);
    test('1 gün, 6 gün, sonra EF ile çarpılır', () {
      var s = ReviewState.initial(t0);
      s = Sm2Scheduler.review(s, RecallGrade.good, t0);
      expect(s.intervalDays, 1);
      s = Sm2Scheduler.review(s, RecallGrade.good, t0);
      expect(s.intervalDays, 6);
      s = Sm2Scheduler.review(s, RecallGrade.good, t0);
      expect(s.intervalDays, 15);
    });
    test('unutulan kart başa döner, kolaylık 1.3 altına inmez', () {
      var s = ReviewState.initial(t0);
      for (var i = 0; i < 10; i++) {
        s = Sm2Scheduler.review(s, RecallGrade.again, t0);
      }
      expect(s.repetitions, 0);
      expect(s.easeFactor, closeTo(1.3, 1e-9));
    });
    test('gün dönümü 04:00', () {
      expect(Sm2Scheduler.dayStart(DateTime(2026, 10, 5, 2), plusDays: 1), DateTime(2026, 10, 5, 4));
    });
  });

  test('sayfa aralığı biçimi', () {
    expect(formatPages([17, 12, 13, 14, 20, 21]), '12–14, 17, 20–21');
  });
}
