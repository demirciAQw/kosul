// Bilgisayarla eşitlemenin sağlayıcıları: depo, istemci, bulucu, eşitleyici
// ve arayüzün izlediği eşleme/durum bilgisi.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/core_providers.dart';
import '../anlik/anlik_providers.dart';
import '../tools/tools_providers.dart';
import 'data/esleme_deposu.dart';
import 'data/koc_bulucu.dart';
import 'data/koc_esitleyici.dart';
import 'data/koc_istemcisi.dart';
import 'domain/koc_baglantisi.dart';

final eslemeDeposuProvider = Provider(
  (ref) => EslemeDeposu(ref.watch(appDatabaseProvider), ref.watch(idGeneratorProvider).next),
);

final kocIstemcisiProvider = Provider((ref) => KocIstemcisi());

final kocBulucuProvider = Provider((ref) => KocBulucu(ref.watch(kocIstemcisiProvider)));

/// Eşli bilgisayar (yoksa null).
final kocEslemesiProvider = FutureProvider<KocEslemesi?>((ref) => ref.watch(eslemeDeposuProvider).esleme());

/// Son eşitleme zamanı ve varsa hatası.
final esitlemeDurumuProvider = FutureProvider<EsitlemeDurumu>((ref) => ref.watch(eslemeDeposuProvider).durum());

final kocEsitleyiciProvider = Provider(
  (ref) => KocEsitleyici(
    depo: ref.watch(eslemeDeposuProvider),
    istemci: ref.watch(kocIstemcisiProvider),
    bulucu: ref.watch(kocBulucuProvider),
    yedekTopla: ref.watch(fullDataCollectorProvider),
    saat: ref.watch(clockProvider),
    kaynaklar: [ref.watch(anlikDeposuProvider)],
    degisti: () {
      ref.invalidate(kocEslemesiProvider);
      ref.invalidate(esitlemeDurumuProvider);
    },
  ),
);
