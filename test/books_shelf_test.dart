import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/core/utils/id_generator.dart';
import 'package:kocum/features/library/data/models/book_template_model.dart';
import 'package:kocum/features/library/domain/progress.dart';
import 'package:kocum/features/library/presentation/books_screen.dart';

class _SeqIds implements IdGenerator {
  var _n = 0;
  @override
  String next() => 'id${_n++}';
}

void main() {
  final expected = {
    'BilgiSarmal_IlkAsama_Fizik.json': (BookShelf.tyt, 132),
    'BilgiSarmal_IlkAsama_Biyoloji.json': (BookShelf.tyt, 129),
    'BilgiSarmal_IlkAsama_Kimya.json': (BookShelf.tyt, 126),
    'Saat_DilBilgisi_Saati.json': (BookShelf.tyt, 68),
    'OrijinalMatematik_BirinciAsama.json': (BookShelf.tyt, 197),
    'Aydin_11_Kimya.json': (BookShelf.ayt, null),
    'MEB_11_Kimya.json': (BookShelf.meb, null),
  };

  for (final e in expected.entries) {
    test('${e.key}: raf ${e.value.$1.label}', () {
      final json = jsonDecode(File('assets/templates/${e.key}').readAsStringSync()) as Map<String, dynamic>;
      final book = BookTemplateModel.fromJson(json).toEntity(ids: _SeqIds(), now: DateTime(2026, 10, 17));
      expect(BookShelf.of(book), e.value.$1);
      final leaves = progressLeaves(book);
      if (e.value.$2 != null) expect(leaves, hasLength(e.value.$2));
      for (final l in leaves) {
        expect(l.pageStart, isNotNull, reason: l.title);
      }
    });
  }
}
