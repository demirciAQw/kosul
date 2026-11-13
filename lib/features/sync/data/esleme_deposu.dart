// Eşleme bilgisi, eşitleme durumu ve bu telefonun kimliği veritabanında
// (app_meta tablosu, JSON) durur. Uygulamanın kendi klasöründedir; başka
// uygulamalar okuyamaz. Eşleme kaldırılınca anahtar buradan silinir.
import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../domain/koc_baglantisi.dart';

class EslemeDeposu {
  EslemeDeposu(this._db, this._yeniId);
  final AppDatabase _db;
  final String Function() _yeniId;

  static const _esleme = 'koc.esleme';
  static const _durum = 'koc.durum';
  static const _cihaz = 'koc.cihaz';

  Future<String?> _oku(String anahtar) async =>
      (await (_db.select(_db.appMeta)..where((m) => m.metaKey.equals(anahtar))).getSingleOrNull())?.metaValue;

  Future<void> _yaz(String anahtar, String deger) =>
      _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion.insert(metaKey: anahtar, metaValue: deger));

  Object? _json(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  Future<KocEslemesi?> esleme() async => KocEslemesi.fromJson(_json(await _oku(_esleme)));

  Future<void> eslemeKaydet(KocEslemesi e) => _yaz(_esleme, jsonEncode(e.toJson()));

  /// Eşleme ve eşitleme izi silinir; telefonun kimliği kalır.
  Future<void> eslemeyiSil() async {
    await (_db.delete(_db.appMeta)..where((m) => m.metaKey.isIn([_esleme, _durum]))).go();
  }

  Future<EsitlemeDurumu> durum() async => EsitlemeDurumu.fromJson(_json(await _oku(_durum)));

  Future<void> durumKaydet(EsitlemeDurumu d) => _yaz(_durum, jsonEncode(d.toJson()));

  /// Bu telefonun kalıcı kimliği (ilk istekte üretilir).
  Future<String> cihazId() async {
    final kayitli = await _oku(_cihaz);
    if (kayitli != null && kayitli.isNotEmpty) return kayitli;
    final yeni = _yeniId();
    await _yaz(_cihaz, yeni);
    return yeni;
  }
}
