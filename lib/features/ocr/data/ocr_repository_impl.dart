import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/ocr.dart';
import '../domain/question_text.dart';

class DriftOcrRepository implements OcrRepository {
  DriftOcrRepository(this._db);
  final AppDatabase _db;

  OcrRecord _toEntity(OcrRow r) {
    Map<String, String> options = const {};
    if (r.optionsJson != null) {
      try {
        final m = jsonDecode(r.optionsJson!) as Map<String, dynamic>;
        options = {for (final e in m.entries) e.key: '${e.value}'};
      } catch (_) {}
    }
    var lines = const <OcrLine>[];
    if (r.linesJson != null) {
      try {
        lines = [
          for (final l in jsonDecode(r.linesJson!) as List)
            OcrLine('${l['t']}',
                left: (l['x'] as num?)?.toDouble() ?? 0,
                top: (l['y'] as num?)?.toDouble() ?? 0,
                height: (l['h'] as num?)?.toDouble() ?? 0),
        ];
      } catch (_) {}
    }
    final hasParse = r.stem != null || options.isNotEmpty;
    return OcrRecord(
      id: r.id,
      ownerType: r.ownerType,
      ownerId: r.ownerId,
      imagePath: r.imagePath,
      status: r.status,
      fullText: r.fullText,
      parsed: hasParse ? ParsedQuestion(stem: r.stem ?? '', number: r.detectedNumber, options: options) : null,
      lines: lines,
      durationMs: r.durationMs,
      error: r.error,
      processedAt: r.processedAt,
    );
  }

  @override
  Stream<Map<String, OcrRecord>> watchAll() =>
      _db.select(_db.ocrResults).watch().map((rows) => {for (final r in rows) r.id: _toEntity(r)});

  @override
  Future<void> save(OcrRecord o) => _db.into(_db.ocrResults).insertOnConflictUpdate(OcrResultsCompanion.insert(
        id: o.id,
        ownerType: o.ownerType,
        ownerId: o.ownerId,
        imagePath: o.imagePath,
        status: o.status,
        fullText: Value(o.fullText),
        stem: Value(o.parsed?.stem),
        optionsJson: Value(o.parsed == null || o.parsed!.options.isEmpty ? null : jsonEncode(o.parsed!.options)),
        detectedNumber: Value(o.parsed?.number),
        linesJson: Value(o.lines.isEmpty ? null : jsonEncode([for (final l in o.lines) l.toJson()])),
        durationMs: Value(o.durationMs),
        error: Value(o.error),
        processedAt: o.processedAt,
      ));

  @override
  Future<void> deleteIds(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(_db.ocrResults)..where((r) => r.id.isIn(list))).go();
  }
}
