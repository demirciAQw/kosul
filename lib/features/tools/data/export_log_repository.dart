import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/export_log.dart';

/// Claude paket günlüğü; app_meta tablosunda JSON olarak.
class ExportLogRepository {
  ExportLogRepository(this._db);
  final AppDatabase _db;
  static const _key = 'export.claude';

  Future<List<ClaudeBatch>> load() async {
    final row = await (_db.select(_db.appMeta)..where((m) => m.metaKey.equals(_key))).getSingleOrNull();
    if (row == null) return const [];
    try {
      final list = jsonDecode(row.metaValue);
      if (list is! List) return const [];
      return [for (final j in list) ClaudeBatch.fromJson(j)].whereType<ClaudeBatch>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<ClaudeBatch> append({
    required DateTime at,
    required DateTime? from,
    required bool full,
    required int questions,
    required int sessions,
  }) async {
    final log = await load();
    final batch = ClaudeBatch(
      number: log.isEmpty ? 1 : log.map((b) => b.number).reduce((a, b) => a > b ? a : b) + 1,
      at: at,
      from: from,
      full: full,
      questions: questions,
      sessions: sessions,
    );
    await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion.insert(
          metaKey: _key,
          metaValue: jsonEncode([for (final b in [...log, batch]) b.toJson()]),
        ));
    return batch;
  }
}
