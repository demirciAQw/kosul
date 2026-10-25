import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';

/// Arama geçmişi (tarayıcıdaki gibi): en yeni başta, tekrarsız, en fazla 25.
class SearchHistoryRepository {
  SearchHistoryRepository(this._db);
  final AppDatabase _db;
  static const _key = 'search.history';
  static const limit = 25;

  Future<List<String>> load() async {
    final row = await (_db.select(_db.appMeta)..where((m) => m.metaKey.equals(_key))).getSingleOrNull();
    if (row == null) return const [];
    try {
      final list = jsonDecode(row.metaValue);
      return list is List ? [for (final e in list) if (e is String) e] : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> save(List<String> items) async {
    final trimmed = items.take(limit).toList();
    await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion.insert(metaKey: _key, metaValue: jsonEncode(trimmed)));
    return trimmed;
  }
}

/// Aramaya yeni bir girdi ekler: aynısı (büyük/küçük harf farkı dahil) üste taşınır.
List<String> pushHistory(List<String> items, String query) {
  final q = query.trim();
  if (q.isEmpty) return items;
  return [q, for (final e in items) if (e.toLowerCase() != q.toLowerCase()) e];
}

/// Arama veri seti: her arama ve sonuca gidiş bir JSON satırı (JSONL).
///
/// Telefonda uygulamanın dış klasöründe durur (Android/data/…/files/kocum_veri);
/// bilgisayara USB ile bağlanınca kopyalanabilir, tüm veri dışa aktarımına da girer.
/// 5 MB'ı aşınca eski dosya ".1" olarak bir yana alınır.
class SearchLog {
  SearchLog({Future<Directory> Function()? baseDir}) : _baseDir = baseDir;

  final Future<Directory> Function()? _baseDir;
  static const fileName = 'arama_kayitlari.jsonl';
  static const _maxBytes = 5 * 1024 * 1024;
  Future<void> _tail = Future<void>.value();

  Future<File> file() async {
    final base = _baseDir != null
        ? await _baseDir()
        : (await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory());
    final dir = Directory('${base.path}/kocum_veri');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$fileName');
  }

  /// Satırlar sırayla yazılır (eşzamanlı yazmalar birbirine karışmaz). Hata
  /// uygulamayı etkilemez; veri seti en iyi çabayla tutulur.
  Future<void> append(Map<String, Object?> event) {
    _tail = _tail.then((_) async {
      try {
        final f = await file();
        if (await f.exists() && await f.length() > _maxBytes) {
          await f.rename('${f.path}.1');
        }
        await f.writeAsString('${jsonEncode(event)}\n', mode: FileMode.append, flush: true);
      } catch (_) {}
    });
    return _tail;
  }
}
