import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/library/data/models/book_template_model.dart';
import 'package:kocum/features/planning/domain/planning.dart';
import 'package:kocum/features/study_session/presentation/tree_selection.dart';

class _SeqIds implements IdGenerator {
  var _n = 0;
  @override
  String next() => 'id${_n++}';
}

BookTemplateModel _load(String name) =>
    BookTemplateModel.fromJson(jsonDecode(File('assets/templates/$name').readAsStringSync()) as Map<String, dynamic>);

void main() {
  group('Hazır kitaplar', () {
    test('Sıfır Risk Paragraf: test bazlı soru sayıları', () {
      final model = _load('345_Sifir_Risk_Paragraf.json');
      expect(model.units, hasLength(7));
      expect(model.units[0].children.first.questions, 20);
      final again = BookTemplateModel.fromJson(jsonDecode(jsonEncode(model.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(again.toJson()), jsonEncode(model.toJson()));

      final book = model.toEntity(ids: _SeqIds(), now: DateTime(2026, 10, 12));
      final root = SelectableNode.fromBook(book);
      final kesfet = root.children.first;
      expect(kesfet.children.first.estimatedQuestions, 20);
      expect(kesfet.estimatedQuestions, 9 * 20);

      // Tek bir test seçmek: optik form 20 soruyla açılır.
      final selection = TreeSelection.empty.setNode(kesfet.children[2], selected: true);
      final drafts = selection.toDrafts([root], selection.computeStates([root]));
      expect(drafts.single.estimatedQuestions, 20);
      expect(drafts.single.label, endsWith('Test 3'));
    });

    test('Aydın 11. Sınıf Kimya: sayfa sayfa içindekiler', () {
      final model = _load('Aydin_11_Kimya.json');
      expect(model.examType, 'AYT');
      expect(model.units, hasLength(3));
      final enerji = model.units.first.children.first;
      expect(enerji.title, 'Enerji');
      expect(enerji.children.first.pageStart, 7);
      expect(enerji.children.first.pageEnd, 12);
    });
  });

  group('Plan türleri', () {
    final today = DateTime(2026, 10, 12, 15);
    test('haftalık 7 gün, aylık bir ay, yıllık bir yıl', () {
      expect(PlanKind.weekly.rangeFrom(today).end, DateTime(2026, 10, 18));
      expect(PlanKind.monthly.rangeFrom(today).end, DateTime(2026, 11, 11));
      expect(PlanKind.yearly.rangeFrom(today).end, DateTime(2027, 10, 11));
    });

    test('tamamlanan plan ilerlemesi tam ve tempo önerisi yok', () {
      final plan = StudyPlan(
        id: 'p',
        title: '1. Plan',
        startsOn: DateTime(2026, 10, 12),
        endsOn: DateTime(2026, 10, 18),
        createdAt: today,
        completedAt: today,
        tasks: const [PlanTask(id: 't', planId: 'p', title: 'Görev')],
      );
      expect(plan.progress, 1);
      expect(plan.paceHint(today), isNull);
      expect(plan.statusText(today), 'Tamamlandı');
    });
  });
}
