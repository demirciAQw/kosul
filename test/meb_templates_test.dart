import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/library/data/models/book_template_model.dart';
import 'package:kocum/features/library/domain/progress.dart';

class _SeqIds implements IdGenerator {
  var _n = 0;
  @override
  String next() => 'id${_n++}';
}

void main() {
  final files = Directory('assets/templates')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('MEB_11_') && f.path.endsWith('.json'))
      .toList();

  test('beş MEB 11. sınıf şablonu bulunur', () {
    expect(files, hasLength(5));
  });

  for (final f in files) {
    test('${f.uri.pathSegments.last} içe aktarılabilir ve yaprakları var', () {
      final model = BookTemplateModel.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      final book = model.toEntity(ids: _SeqIds(), now: DateTime(2026, 10, 17));
      expect(book.roots, isNotEmpty);
      expect(progressLeaves(book), isNotEmpty);
      for (final leaf in progressLeaves(book)) {
        expect(leaf.pageStart, isNotNull, reason: leaf.title);
        expect(leaf.pageEnd! >= leaf.pageStart!, isTrue, reason: leaf.title);
      }
    });
  }
}
