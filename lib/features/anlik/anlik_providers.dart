// Anlık sağlayıcıları: depo, canlı listeler (anlık, etiket, bağ) ve hangi
// modun (ana uygulama / Anlık) en son açık olduğu.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/di/core_providers.dart';
import 'data/anlik_deposu.dart';
import 'domain/anlik.dart';

final anlikDeposuProvider = Provider(
  (ref) => AnlikDeposu(ref.watch(appDatabaseProvider), ref.watch(idGeneratorProvider), ref.watch(clockProvider)),
);

/// Bütün anlıklar (silinenler dahil, yeniden eskiye). Arayüz silinmişleri süzer.
final anliklarProvider = StreamProvider<List<Anlik>>((ref) => ref.watch(anlikDeposuProvider).anliklariIzle());

final etiketlerProvider = StreamProvider<List<Etiket>>((ref) => ref.watch(anlikDeposuProvider).etiketleriIzle());

final baglarProvider = StreamProvider<List<Bag>>((ref) => ref.watch(anlikDeposuProvider).baglariIzle());

// ───────────────────────── Son açılan mod ─────────────────────────

const _modAnahtari = 'arayuz.mod';

/// Uygulama açılırken okunur (main.dart): 'anlik' ise Anlık ekranı açılır.
Future<bool> anlikModundaMi(AppDatabase db) async {
  final r = await (db.select(db.appMeta)..where((m) => m.metaKey.equals(_modAnahtari))).getSingleOrNull();
  return r?.metaValue == 'anlik';
}

Future<void> modKaydet(AppDatabase db, {required bool anlik}) => db
    .into(db.appMeta)
    .insertOnConflictUpdate(
      AppMetaCompanion(metaKey: const Value(_modAnahtari), metaValue: Value(anlik ? 'anlik' : 'ana')),
    );

/// main.dart'ta okunan başlangıç modu (router ilk sayfayı buna göre seçer).
final baslangictaAnlikProvider = Provider<bool>((ref) => false);
