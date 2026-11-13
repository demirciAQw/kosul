// Anlık verisinin veritabanı katmanı (Drift): anlıklar, etiketler, bağlar.
//
// Kurallar domain/ içinde (saf Dart); burada sadece okuma, yazma ve işaretleme
// var. Her değişiklik `guncelleme`yi yeniler ve `esitlenmedi = true` yapar ki
// bir sonraki eşitlemede bilgisayara gitsin. Hiçbir şey kalıcı silinmez.
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/text/turkish_text.dart';
import '../../../core/utils/id_generator.dart';
import '../../sync/domain/koc_baglantisi.dart';
import '../domain/anlik.dart';
import '../domain/anlik_esitleme.dart';
import '../domain/etiket_kurallari.dart';
import '../domain/etiket_metni.dart';

class EtiketHatasi implements Exception {
  const EtiketHatasi(this.mesaj);
  final String mesaj;
  @override
  String toString() => mesaj;
}

Anlik anlikSatirdan(AnlikRow r) => Anlik(
  id: r.id,
  metin: r.metin,
  olusturma: r.olusturma,
  guncelleme: r.guncelleme,
  duygu: r.duygu,
  cihaz: r.cihaz,
  silindi: r.silindi,
  esitlenmedi: r.esitlenmedi,
);

Etiket etiketSatirdan(EtiketRow r) => Etiket(
  id: r.id,
  ad: r.ad,
  normAd: r.normAd,
  tur: EtiketTur.coz(r.tur),
  renk: r.renk,
  olusturan: r.olusturan,
  olusturma: r.olusturma,
  guncelleme: r.guncelleme,
  silindi: r.silindi,
  esitlenmedi: r.esitlenmedi,
);

Bag bagSatirdan(BagRow r) => Bag(
  id: r.id,
  tip: BagTip.coz(r.tip),
  kaynakTur: UcTur.coz(r.kaynakTur),
  kaynakId: r.kaynakId,
  hedefTur: UcTur.coz(r.hedefTur),
  hedefId: r.hedefId,
  neden: BagNeden.coz(r.neden),
  durum: BagDurum.coz(r.durum),
  puan: r.puan,
  olusturma: r.olusturma,
  guncelleme: r.guncelleme,
  silindi: r.silindi,
  esitlenmedi: r.esitlenmedi,
);

AnliklarCompanion _anlikYaz(Anlik a) => AnliklarCompanion.insert(
  id: a.id,
  metin: a.metin,
  olusturma: a.olusturma,
  guncelleme: a.guncelleme,
  duygu: Value(a.duygu),
  cihaz: Value(a.cihaz),
  silindi: Value(a.silindi),
  esitlenmedi: Value(a.esitlenmedi),
);

EtiketlerCompanion _etiketYaz(Etiket e) => EtiketlerCompanion.insert(
  id: e.id,
  ad: e.ad,
  normAd: e.normAd,
  tur: Value(e.tur.name),
  renk: Value(e.renk),
  olusturan: Value(e.olusturan),
  olusturma: e.olusturma,
  guncelleme: e.guncelleme,
  silindi: Value(e.silindi),
  esitlenmedi: Value(e.esitlenmedi),
);

BaglarCompanion _bagYaz(Bag b) => BaglarCompanion.insert(
  id: b.id,
  tip: b.tip.name,
  kaynakTur: b.kaynakTur.name,
  kaynakId: b.kaynakId,
  hedefTur: b.hedefTur.name,
  hedefId: b.hedefId,
  neden: Value(b.neden.name),
  durum: Value(b.durum.name),
  puan: Value(b.puan),
  olusturma: b.olusturma,
  guncelleme: b.guncelleme,
  silindi: Value(b.silindi),
  esitlenmedi: Value(b.esitlenmedi),
);

class AnlikDeposu implements EsitKayitKaynagi {
  AnlikDeposu(this._db, this._id, this._saat, {this.cihaz = 'telefon'});
  final AppDatabase _db;
  final IdGenerator _id;
  final Clock _saat;
  final String cihaz;

  // ───────────── okuma ─────────────

  Stream<List<Anlik>> anliklariIzle() => (_db.select(
    _db.anliklar,
  )..orderBy([(a) => OrderingTerm.desc(a.olusturma)])).watch().map((r) => r.map(anlikSatirdan).toList());

  Stream<List<Etiket>> etiketleriIzle() => _db.select(_db.etiketler).watch().map((r) => r.map(etiketSatirdan).toList());

  Stream<List<Bag>> baglariIzle() => _db.select(_db.baglar).watch().map((r) => r.map(bagSatirdan).toList());

  Future<List<Anlik>> anliklar() async => (await _db.select(_db.anliklar).get()).map(anlikSatirdan).toList();
  Future<List<Etiket>> etiketler() async => (await _db.select(_db.etiketler).get()).map(etiketSatirdan).toList();
  Future<List<Bag>> baglar() async => (await _db.select(_db.baglar).get()).map(bagSatirdan).toList();

  Future<List<Bag>> _anlikBaglari(String anlikId) async => (await (_db.select(
    _db.baglar,
  )..where((b) => b.kaynakId.equals(anlikId) & b.tip.equals('etiketli'))).get()).map(bagSatirdan).toList();

  // ───────────── anlık ─────────────

  /// Yeni anlık yazar ya da [id] verilmişse günceller. Metindeki ((…)) bağları
  /// yeniden hesaplanır; [seritEtiketleri] şerit bağı olarak eklenir.
  /// Adı bilinmeyen ((…)) bağ almaz (yeni etiket penceresinde vazgeçilmiştir).
  Future<String> anlikKaydet({
    String? id,
    required String metin,
    int? duygu,
    Set<String> seritEtiketleri = const {},
  }) async {
    final simdi = _saat();
    final anlikId = id ?? _id.next();
    await _db.transaction(() async {
      final eski = await (_db.select(_db.anliklar)..where((a) => a.id.equals(anlikId))).getSingleOrNull();
      await _db
          .into(_db.anliklar)
          .insertOnConflictUpdate(
            _anlikYaz(
              Anlik(
                id: anlikId,
                metin: metin,
                olusturma: eski?.olusturma ?? simdi,
                guncelleme: simdi,
                duygu: duygu,
                cihaz: eski?.cihaz ?? cihaz,
              ),
            ),
          );
      await _metinBaglariniYenile(anlikId, metin, simdi);
      for (final e in seritEtiketleri) {
        await _seritBagi(anlikId, e, simdi);
      }
    });
    return anlikId;
  }

  Future<void> _metinBaglariniYenile(String anlikId, String metin, DateTime simdi) async {
    final etiketler = await this.etiketler();
    final adla = {
      for (final e in etiketler)
        if (!e.silindi) e.normAd: e.id,
    };
    final metindekiler = {
      for (final n in metinEtiketAdlari(metin))
        if (adla[n] != null) adla[n]!,
    };
    final fark = metinBagFarki(metindekiler: metindekiler, mevcut: await _anlikBaglari(anlikId));
    for (final b in fark.sil) {
      await _bagGuncelle(b.id, silindi: true, simdi: simdi);
    }
    for (final b in fark.geriGetir) {
      await _bagGuncelle(b.id, silindi: false, simdi: simdi);
    }
    for (final e in fark.ekle) {
      await _yeniBag(BagTip.etiketli, UcTur.anlik, anlikId, UcTur.etiket, e, BagNeden.metin, simdi);
    }
  }

  Future<void> _seritBagi(String anlikId, String etiketId, DateTime simdi) async {
    final mevcut = (await _anlikBaglari(
      anlikId,
    )).where((b) => b.hedefId == etiketId && b.neden != BagNeden.metin).toList();
    final etkin = mevcut.where((b) => !b.silindi);
    if (etkin.isNotEmpty) return;
    if (mevcut.isNotEmpty) {
      await _bagGuncelle(mevcut.first.id, silindi: false, simdi: simdi);
    } else {
      await _yeniBag(BagTip.etiketli, UcTur.anlik, anlikId, UcTur.etiket, etiketId, BagNeden.serit, simdi);
    }
  }

  /// Şeritten etiket ekle (kayıtlı bir anlığa).
  Future<void> seritEtiketiEkle(String anlikId, Set<String> etiketIds) async {
    final simdi = _saat();
    await _db.transaction(() async {
      for (final e in etiketIds) {
        await _seritBagi(anlikId, e, simdi);
      }
    });
  }

  /// Çipteki ×: bağ yumuşak silinir, etiket kalır.
  Future<void> bagKaldir(String bagId) => _bagGuncelle(bagId, silindi: true, simdi: _saat());

  Future<void> anlikSil(String id) async {
    await (_db.update(_db.anliklar)..where((a) => a.id.equals(id))).write(
      AnliklarCompanion(silindi: const Value(true), guncelleme: Value(_saat()), esitlenmedi: const Value(true)),
    );
  }

  Future<void> _bagGuncelle(String id, {required bool silindi, required DateTime simdi}) =>
      (_db.update(_db.baglar)..where((b) => b.id.equals(id))).write(
        BaglarCompanion(silindi: Value(silindi), guncelleme: Value(simdi), esitlenmedi: const Value(true)),
      );

  Future<String> _yeniBag(
    BagTip tip,
    UcTur kTur,
    String k,
    UcTur hTur,
    String h,
    BagNeden neden,
    DateTime simdi,
  ) async {
    final id = _id.next();
    await _db
        .into(_db.baglar)
        .insert(
          _bagYaz(
            Bag(
              id: id,
              tip: tip,
              kaynakTur: kTur,
              kaynakId: k,
              hedefTur: hTur,
              hedefId: h,
              neden: neden,
              olusturma: simdi,
              guncelleme: simdi,
            ),
          ),
        );
    return id;
  }

  // ───────────── etiket ─────────────

  /// Yeni etiket penceresinde "Oluştur". Aynı adla etiket varsa hata.
  Future<Etiket> etiketOlustur({
    required String ad,
    EtiketTur tur = EtiketTur.diger,
    int? renk,
    String? ustId,
    String olusturan = 'ben',
  }) async {
    final temiz = etiketAdiDuzelt(ad);
    if (!gecerliEtiketAdi(temiz)) throw const EtiketHatasi('Etiket adı boş ya da çok uzun.');
    final simdi = _saat();
    late Etiket yeni;
    await _db.transaction(() async {
      final hepsi = await etiketler();
      if (adlaBul(hepsi, temiz) != null) throw EtiketHatasi('"$temiz" adında bir etiket zaten var.');
      yeni = Etiket(
        id: _id.next(),
        ad: temiz,
        normAd: normalizeTr(temiz),
        tur: tur,
        renk: renk,
        olusturan: olusturan,
        olusturma: simdi,
        guncelleme: simdi,
      );
      await _db.into(_db.etiketler).insert(_etiketYaz(yeni));
      if (ustId != null) await _ustBagi(yeni.id, ustId, simdi);
      // Bu ad metinlerde zaten ((…)) olarak geçiyor olabilir: bağları kur.
      for (final a in await anliklar()) {
        if (!a.silindi && metinEtiketAdlari(a.metin).contains(yeni.normAd)) {
          await _metinBaglariniYenile(a.id, a.metin, simdi);
        }
      }
    });
    return yeni;
  }

  /// [altId] etiketini [ustId]'nin altına koyar. Döngü olacaksa hata.
  Future<void> ustEkle(String altId, String ustId) async {
    final simdi = _saat();
    await _db.transaction(() => _ustBagi(altId, ustId, simdi));
  }

  Future<void> _ustBagi(String altId, String ustId, DateTime simdi) async {
    final baglar = await this.baglar();
    if (donguOlurMu(altId: altId, ustId: ustId, baglar: baglar)) {
      throw const EtiketHatasi('Bu bağ döngü olur: bir etiket kendi altının altına giremez.');
    }
    final mevcut = baglar.where((b) => b.tip == BagTip.ust && b.kaynakId == altId && b.hedefId == ustId).toList();
    if (mevcut.any((b) => !b.silindi)) return;
    if (mevcut.isNotEmpty) {
      await _bagGuncelle(mevcut.first.id, silindi: false, simdi: simdi);
    } else {
      await _yeniBag(BagTip.ust, UcTur.etiket, altId, UcTur.etiket, ustId, BagNeden.elle, simdi);
    }
  }

  /// Etiket silme: plan saf fonksiyonda hesaplanır, burada uygulanır.
  Future<EtiketSilmePlani> etiketSil(String etiketId, {required bool altlariyla}) async {
    final simdi = _saat();
    late EtiketSilmePlani plan;
    await _db.transaction(() async {
      plan = etiketSilmePlani(
        etiketId: etiketId,
        altlariyla: altlariyla,
        etiketler: await etiketler(),
        baglar: await baglar(),
        anliklar: await anliklar(),
      );
      await (_db.update(_db.etiketler)..where((e) => e.id.isIn(plan.etiketler))).write(
        EtiketlerCompanion(silindi: const Value(true), guncelleme: Value(simdi), esitlenmedi: const Value(true)),
      );
      await (_db.update(_db.baglar)..where((b) => b.id.isIn(plan.baglar))).write(
        BaglarCompanion(silindi: const Value(true), guncelleme: Value(simdi), esitlenmedi: const Value(true)),
      );
      for (final e in plan.metniDegisenler.entries) {
        await (_db.update(_db.anliklar)..where((a) => a.id.equals(e.key))).write(
          AnliklarCompanion(metin: Value(e.value), guncelleme: Value(simdi), esitlenmedi: const Value(true)),
        );
      }
    });
    return plan;
  }

  /// "Son silinenler"den geri al: etiket ve onunla aynı anda silinen bağlar
  /// döner. Metin düz yazıya dönmüş olduğundan metin bağları şerit bağı olur.
  Future<void> etiketGeriAl(String etiketId) async {
    final simdi = _saat();
    await _db.transaction(() async {
      final e = await (_db.select(_db.etiketler)..where((x) => x.id.equals(etiketId))).getSingleOrNull();
      if (e == null || !e.silindi) return;
      if (adlaBul(await etiketler(), e.ad) != null) {
        throw EtiketHatasi('"${e.ad}" adında başka bir etiket var; önce onu yeniden adlandır.');
      }
      final silmeAni = e.guncelleme;
      await (_db.update(_db.etiketler)..where((x) => x.id.equals(etiketId))).write(
        EtiketlerCompanion(silindi: const Value(false), guncelleme: Value(simdi), esitlenmedi: const Value(true)),
      );
      final baglar =
          await (_db.select(_db.baglar)..where(
                (b) =>
                    b.silindi.equals(true) &
                    b.guncelleme.equals(silmeAni) &
                    (b.hedefId.equals(etiketId) | b.kaynakId.equals(etiketId)),
              ))
              .get();
      for (final b in baglar) {
        await (_db.update(_db.baglar)..where((x) => x.id.equals(b.id))).write(
          BaglarCompanion(
            silindi: const Value(false),
            neden: Value(b.neden == 'metin' ? 'serit' : b.neden),
            guncelleme: Value(simdi),
            esitlenmedi: const Value(true),
          ),
        );
      }
    });
  }

  // ───────────── içe aktarma ─────────────

  /// Obsidian `Anlar/*.md` dosyaları. Metindeki bilinmeyen ((…)) adlar için
  /// etiket kendiliğinden (tür: diğer) oluşturulur. Aynı dosya ikinci kez
  /// aktarılırsa atlanır. Döner: eklenen ve atlanan sayısı.
  Future<({int eklenen, int atlanan})> mdIceAktar(List<({String ad, String icerik, DateTime zaman})> dosyalar) async {
    var eklenen = 0, atlanan = 0;
    await _db.transaction(() async {
      final mevcut = {for (final a in await anliklar()) a.id};
      for (final d in dosyalar) {
        final okunan = mdAnlikOku(d.icerik, d.zaman);
        final id = mdAnlikId(d.ad);
        if (okunan == null || mevcut.contains(id)) {
          atlanan++;
          continue;
        }
        for (final atif in metinEtiketleri(okunan.metin)) {
          if (adlaBul(await etiketler(), atif.ad) == null) await etiketOlustur(ad: atif.ad);
        }
        final simdi = _saat();
        await _db
            .into(_db.anliklar)
            .insert(
              _anlikYaz(
                Anlik(
                  id: id,
                  metin: okunan.metin,
                  olusturma: okunan.zaman,
                  guncelleme: simdi,
                  duygu: okunan.duygu,
                  cihaz: 'obsidian',
                ),
              ),
            );
        await _metinBaglariniYenile(id, okunan.metin, simdi);
        mevcut.add(id);
        eklenen++;
      }
    });
    return (eklenen: eklenen, atlanan: atlanan);
  }

  // ───────────── eşitleme ─────────────

  /// Son eşitlemeden beri değişenler (silinenler dahil), istek biçiminde.
  @override
  Future<Map<String, List<Map<String, Object?>>>> esitlenecekler() async {
    final a = await (_db.select(_db.anliklar)..where((x) => x.esitlenmedi.equals(true))).get();
    final e = await (_db.select(_db.etiketler)..where((x) => x.esitlenmedi.equals(true))).get();
    final b = await (_db.select(_db.baglar)..where((x) => x.esitlenmedi.equals(true))).get();
    return {
      if (a.isNotEmpty) 'anliklar': [for (final r in a) anlikJson(anlikSatirdan(r))],
      if (e.isNotEmpty) 'etiketler': [for (final r in e) etiketJson(etiketSatirdan(r))],
      if (b.isNotEmpty) 'baglar': [for (final r in b) bagJson(bagSatirdan(r))],
    };
  }

  /// Gönderilenler eşitlendi: istek yoldayken yeniden değişmediyse işaret kalkar.
  @override
  Future<void> esitlendi(Map<String, List<Map<String, Object?>>> gonderilen) async {
    await _db.transaction(() async {
      for (final t in gonderilen.entries) {
        if (!const {'anliklar', 'etiketler', 'baglar'}.contains(t.key)) continue;
        for (final k in t.value) {
          final id = k['id'] as String;
          final g = DateTime.parse(k['guncelleme'] as String).toLocal();
          if (t.key == 'anliklar') {
            await (_db.update(_db.anliklar)..where((x) => x.id.equals(id) & x.guncelleme.equals(g))).write(
              const AnliklarCompanion(esitlenmedi: Value(false)),
            );
          } else if (t.key == 'etiketler') {
            await (_db.update(_db.etiketler)..where((x) => x.id.equals(id) & x.guncelleme.equals(g))).write(
              const EtiketlerCompanion(esitlenmedi: Value(false)),
            );
          } else if (t.key == 'baglar') {
            await (_db.update(_db.baglar)..where((x) => x.id.equals(id) & x.guncelleme.equals(g))).write(
              const BaglarCompanion(esitlenmedi: Value(false)),
            );
          }
        }
      }
    });
  }

  /// Bilgisayardan gelenler. Çakışma kuralı `sunucudanGelenleriUygula`da;
  /// aynı normalize adlı etiketler birleştirilir. Bozuk kayıt atlanır.
  @override
  Future<int> gelenleriUygula(Map<String, List<Map<String, Object?>>> tablolar) async {
    final simdi = _saat();
    var yazilan = 0;
    await _db.transaction(() async {
      final yereller = {
        'anliklar': {
          for (final a in await anliklar())
            a.id: EsitKayit(id: a.id, veri: anlikJson(a), silindi: a.silindi, esitlenmedi: a.esitlenmedi),
        },
        'etiketler': {
          for (final e in await etiketler())
            e.id: EsitKayit(id: e.id, veri: etiketJson(e), silindi: e.silindi, esitlenmedi: e.esitlenmedi),
        },
        'baglar': {
          for (final b in await baglar())
            b.id: EsitKayit(id: b.id, veri: bagJson(b), silindi: b.silindi, esitlenmedi: b.esitlenmedi),
        },
      };
      for (final tablo in const ['etiketler', 'anliklar', 'baglar']) {
        final yazilacak = sunucudanGelenleriUygula(
          yerel: yereller[tablo]!,
          gelenler: tablolar[tablo] ?? const [],
          yeniId: _id.next,
        );
        for (final k in yazilacak) {
          // Kopyalar (esitlenmedi) sunucuya geri gider; gelenler eşitlenmiş sayılır.
          switch (tablo) {
            case 'anliklar':
              final a = anlikOku(k.veri, simdi);
              if (a == null) continue;
              await _db
                  .into(_db.anliklar)
                  .insertOnConflictUpdate(_anlikYaz(k.esitlenmedi ? _anlikIsaretli(a, simdi) : a));
            case 'etiketler':
              final e = etiketOku(k.veri, simdi);
              if (e == null) continue;
              await _db.into(_db.etiketler).insertOnConflictUpdate(_etiketYaz(e));
            case 'baglar':
              final b = bagOku(k.veri, simdi);
              if (b == null) continue;
              await _db.into(_db.baglar).insertOnConflictUpdate(_bagYaz(b));
          }
          yazilan++;
        }
      }
      await _etiketleriBirlestir(simdi);
    });
    return yazilan;
  }

  Anlik _anlikIsaretli(Anlik a, DateTime simdi) => Anlik(
    id: a.id,
    metin: a.metin,
    olusturma: a.olusturma,
    guncelleme: simdi,
    duygu: a.duygu,
    cihaz: a.cihaz,
    silindi: a.silindi,
  );

  /// Aynı normalize adlı etiketler: bağlar kalana taşınır, kaybeden silinir.
  Future<void> _etiketleriBirlestir(DateTime simdi) async {
    final harita = etiketBirlestirmeHaritasi(await etiketler());
    for (final e in harita.entries) {
      await etiketleriBirlestir(kaybeden: e.key, kalan: e.value, simdi: simdi);
    }
  }

  /// [kaybeden]'in bağları [kalan]'a taşınır, [kaybeden] yumuşak silinir.
  Future<void> etiketleriBirlestir({required String kaybeden, required String kalan, DateTime? simdi}) async {
    final t = simdi ?? _saat();
    final degisen = BaglarCompanion(guncelleme: Value(t), esitlenmedi: const Value(true));
    await (_db.update(_db.baglar)..where((b) => b.hedefId.equals(kaybeden) & b.hedefTur.equals('etiket'))).write(
      degisen.copyWith(hedefId: Value(kalan)),
    );
    await (_db.update(_db.baglar)..where((b) => b.kaynakId.equals(kaybeden) & b.kaynakTur.equals('etiket'))).write(
      degisen.copyWith(kaynakId: Value(kalan)),
    );
    // Kendi kendine üst bağı oluştuysa (kalan → kalan) silinir.
    await (_db.update(_db.baglar)..where((b) => b.kaynakId.equals(kalan) & b.hedefId.equals(kalan))).write(
      degisen.copyWith(silindi: const Value(true)),
    );
    await (_db.update(_db.etiketler)..where((e) => e.id.equals(kaybeden))).write(
      EtiketlerCompanion(silindi: const Value(true), guncelleme: Value(t), esitlenmedi: const Value(true)),
    );
  }
}
