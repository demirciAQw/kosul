import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/settings.dart';

/// Ayarlar, veritabanındaki anahtar-değer tablosunda (app_meta) JSON olarak durur.
class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  static const _key = 'app.settings';

  Future<AppSettings> load() async {
    final row = await (_db.select(_db.appMeta)..where((m) => m.metaKey.equals(_key))).getSingleOrNull();
    if (row == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(row.metaValue) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) => _db.into(_db.appMeta).insertOnConflictUpdate(
        AppMetaCompanion.insert(metaKey: _key, metaValue: jsonEncode(s.toJson())),
      );
}
