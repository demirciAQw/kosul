// Noktasal grafiğin verisi (saf Dart): düğümler, kenarlar ve başlangıç yerleri.
//
// `grafVerisi(gorunum, anliklar, etiketler, baglar)` her görünüm için aynı
// girdiden aynı sonucu verir (rastgelelik yok). Başlangıç yerleşimi tarihe
// göre bir sarmaldır: eskiler dışta ve solda, yeniler içte ve sağda.
// Sonra kuvvet_duzeni.dart düğümleri bağlara göre biraz kaydırır.
import 'dart:math' as math;

import '../../../core/utils/formatters.dart';
import 'anlik.dart';
import 'etiket_kurallari.dart';

enum GrafGorunum {
  baglar('Bağlar'),
  takvim('Takvim'),
  metinIci('Metin içi'),
  anaEtiketler('Ana etiketler'),
  etiketAgaci('Etiket ağacı');

  const GrafGorunum(this.ad);
  final String ad;

  static GrafGorunum coz(Object? s) => values.firstWhere((g) => g.name == s, orElse: () => GrafGorunum.baglar);
}

enum DugumTur { anlik, etiket, gun }

class Dugum {
  const Dugum({
    required this.id,
    required this.tur,
    required this.x,
    required this.y,
    this.yaricap = 4,
    this.ad = '',
    this.etiket,
    this.duygu,
    this.vurgulu = false,
    this.sabit = true,
    this.katli = false,
  });

  /// "anlik:…", "etiket:…" ya da "gun:2026-11-14".
  final String id;
  final DugumTur tur;

  /// Başlangıç (sarmal) konumu; kuvvet düzeni bu noktaya yayla bağlıdır.
  final double x;
  final double y;
  final double yaricap;
  final String ad;

  /// Etiket düğümünde etiketin kendisi (renk ve tür için).
  final Etiket? etiket;

  /// Gün düğümünde o günün ortalama duygusu; anlıkta kendi duygusu.
  final double? duygu;

  /// Takvim görünümünde seçili etiketi taşıyan anlık.
  final bool vurgulu;

  /// Sarmal yerine bağlı mı (anlık ve gün düğümleri). Etiketler serbesttir.
  final bool sabit;

  /// Ana etiketler görünümünde altları katlanmış düğüm (dokununca açılır).
  final bool katli;
}

class Kenar {
  const Kenar(this.a, this.b, {this.soluk = false, this.agirlik = 1});
  final String a;
  final String b;

  /// `onerildi` durumundaki bağ: kesikli ve soluk çizilir.
  final bool soluk;
  final double agirlik;
}

class GrafVerisi {
  const GrafVerisi(this.dugumler, this.kenarlar);
  final List<Dugum> dugumler;
  final List<Kenar> kenarlar;
}

/// Sarmalın dış yarıçapı (dünya birimi). Çizimde ekrana sığdırılır.
const sarmalR = 500.0;

/// Sarmal katsayısı: θ = π − t·π·k.
const sarmalK = 1.5;

/// t ∈ [0,1] (tarihteki sıra) için sarmal noktası. θ soldan başlar, üstten
/// geçerek sağa ilerler; yarıçap dıştan içe azalır: r = R·(1 − 0,75t).
/// Ekran koordinatı: y aşağı doğru artar, bu yüzden üst = eksi y.
({double x, double y}) sarmalNoktasi(double t, {double r0 = sarmalR, double k = sarmalK}) {
  final teta = math.pi - t * math.pi * k;
  final r = r0 * (1 - 0.75 * t);
  return (x: r * math.cos(teta), y: -r * math.sin(teta));
}

/// Takvim sarmalı: her tur bir hafta (7 gün = 360°), dıştan içe.
({double x, double y}) takvimNoktasi(int gun, int gunSayisi, {double r0 = sarmalR}) {
  final t = gunSayisi <= 1 ? 0.0 : gun / (gunSayisi - 1);
  final teta = math.pi - gun / 7 * 2 * math.pi;
  final r = r0 * (1 - 0.75 * t);
  return (x: r * math.cos(teta), y: -r * math.sin(teta));
}

String anlikDugumu(String id) => 'anlik:$id';
String etiketDugumu(String id) => 'etiket:$id';

/// Görünüme göre grafik. [anliklar] arama ve filtre sonucudur (filtre yoksa hepsi).
/// [acikAnaEtiketler]: ana etiketler görünümünde açılmış (altları görünen) etiketler.
/// [vurguluEtiketler]: takvimde anlıkları renklenecek etiketler (altları dahil).
GrafVerisi grafVerisi(
  GrafGorunum gorunum, {
  required List<Anlik> anliklar,
  required List<Etiket> etiketler,
  required List<Bag> baglar,
  Set<String> acikAnaEtiketler = const {},
  Set<String> vurguluEtiketler = const {},
}) {
  final etkinEtiket = {
    for (final e in etiketler)
      if (!e.silindi) e.id: e,
  };
  final etkinBag = [
    for (final b in baglar)
      if (!b.silindi && b.durum != BagDurum.reddedildi) b,
  ];
  final sirali =
      [
        for (final a in anliklar)
          if (!a.silindi) a,
      ]..sort((a, b) {
        final c = a.olusturma.compareTo(b.olusturma);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
  return switch (gorunum) {
    GrafGorunum.baglar => _baglar(sirali, etkinEtiket, etkinBag, sadeceMetin: false),
    GrafGorunum.metinIci => _baglar(sirali, etkinEtiket, etkinBag, sadeceMetin: true),
    GrafGorunum.takvim => _takvim(sirali, etkinBag, vurguluEtiketler),
    GrafGorunum.anaEtiketler => _anaEtiketler(sirali, etkinEtiket, etkinBag, acikAnaEtiketler),
    GrafGorunum.etiketAgaci => _etiketAgaci(etkinEtiket, etkinBag),
  };
}

List<Dugum> _anlikDugumleri(List<Anlik> sirali) {
  final n = sirali.length;
  final dugumler = <Dugum>[];
  for (var i = 0; i < n; i++) {
    final p = sarmalNoktasi(n <= 1 ? 0 : i / (n - 1));
    final a = sirali[i];
    dugumler.add(
      Dugum(id: anlikDugumu(a.id), tur: DugumTur.anlik, x: p.x, y: p.y, ad: a.metin, duygu: a.duygu?.toDouble()),
    );
  }
  return dugumler;
}

/// Etiket düğümü bağlı anlıkların ortalamasından başlar; anlığı yoksa
/// merkezin çevresinde, ada göre sıralı bir halkaya konur.
Dugum _etiketDugumu(Etiket e, List<({double x, double y})> komsular, int sira, int toplam, {double boyut = 0}) {
  double x, y;
  if (komsular.isNotEmpty) {
    x = komsular.map((p) => p.x).reduce((a, b) => a + b) / komsular.length;
    y = komsular.map((p) => p.y).reduce((a, b) => a + b) / komsular.length;
  } else {
    final teta = 2 * math.pi * sira / math.max(1, toplam);
    x = sarmalR * 0.15 * math.cos(teta);
    y = sarmalR * 0.15 * math.sin(teta);
  }
  final sayi = boyut > 0 ? boyut : komsular.length.toDouble();
  return Dugum(
    id: etiketDugumu(e.id),
    tur: DugumTur.etiket,
    x: x,
    y: y,
    yaricap: 8 + 3 * math.sqrt(sayi),
    ad: e.ad,
    etiket: e,
    sabit: false,
  );
}

GrafVerisi _baglar(List<Anlik> sirali, Map<String, Etiket> etiketler, List<Bag> baglar, {required bool sadeceMetin}) {
  final anlikD = _anlikDugumleri(sirali);
  final konum = {for (final d in anlikD) d.id: (x: d.x, y: d.y)};
  final kenarlar = <Kenar>[];
  final komsular = <String, List<({double x, double y})>>{};
  for (final b in baglar) {
    if (b.tip == BagTip.etiketli) {
      if (sadeceMetin && b.neden != BagNeden.metin) continue;
      final a = konum[anlikDugumu(b.kaynakId)];
      if (a == null || !etiketler.containsKey(b.hedefId)) continue;
      (komsular[b.hedefId] ??= []).add(a);
      kenarlar.add(Kenar(anlikDugumu(b.kaynakId), etiketDugumu(b.hedefId), soluk: b.durum == BagDurum.onerildi));
    } else if (b.tip == BagTip.ilgili && !sadeceMetin) {
      if (konum[anlikDugumu(b.kaynakId)] == null || konum[anlikDugumu(b.hedefId)] == null) continue;
      kenarlar.add(Kenar(anlikDugumu(b.kaynakId), anlikDugumu(b.hedefId), soluk: b.durum == BagDurum.onerildi));
    }
  }
  // Bağlar görünümünde bütün etiketler; metin içinde sadece metinde geçenler.
  final gosterilecek = sadeceMetin ? komsular.keys.toSet() : etiketler.keys.toSet();
  if (!sadeceMetin) {
    for (final b in baglar) {
      if (b.tip == BagTip.ust && gosterilecek.contains(b.kaynakId) && gosterilecek.contains(b.hedefId)) {
        kenarlar.add(Kenar(etiketDugumu(b.kaynakId), etiketDugumu(b.hedefId), soluk: b.durum == BagDurum.onerildi));
      }
    }
  }
  final ids = gosterilecek.toList()..sort((a, b) => etiketler[a]!.normAd.compareTo(etiketler[b]!.normAd));
  final etiketD = [
    for (var i = 0; i < ids.length; i++) _etiketDugumu(etiketler[ids[i]]!, komsular[ids[i]] ?? const [], i, ids.length),
  ];
  return GrafVerisi([...anlikD, ...etiketD], kenarlar);
}

GrafVerisi _takvim(List<Anlik> sirali, List<Bag> baglar, Set<String> vurguluEtiketler) {
  if (sirali.isEmpty) return const GrafVerisi([], []);
  DateTime gunu(DateTime d) => DateTime(d.year, d.month, d.day);
  final ilk = gunu(sirali.first.olusturma);
  final son = gunu(sirali.last.olusturma);
  // En fazla ~1 yıl gün düğümü (çok eski veride sarmal okunmaz hale gelmesin).
  final gunSayisi = math.min(370, son.difference(ilk).inDays + 1);
  final basGun = son.subtract(Duration(days: gunSayisi - 1));
  final hedefler = <String>{for (final id in vurguluEtiketler) ...altlariylaBirlikte(id, baglar)};
  final vurgulu = {
    for (final b in baglar)
      if (b.tip == BagTip.etiketli && hedefler.contains(b.hedefId)) b.kaynakId,
  };
  final gunAnliklari = <int, List<Anlik>>{};
  for (final a in sirali) {
    final i = gunu(a.olusturma).difference(basGun).inDays;
    if (i < 0) continue;
    (gunAnliklari[i] ??= []).add(a);
  }
  final dugumler = <Dugum>[];
  final kenarlar = <Kenar>[];
  for (var i = 0; i < gunSayisi; i++) {
    final g = basGun.add(Duration(days: i));
    final p = takvimNoktasi(i, gunSayisi);
    final liste = gunAnliklari[i] ?? const <Anlik>[];
    final duygular = [
      for (final a in liste)
        if (a.duygu != null) a.duygu!,
    ];
    final haftaBasi = g.weekday == DateTime.monday;
    final id = 'gun:${g.toIso8601String().substring(0, 10)}';
    dugumler.add(
      Dugum(
        id: id,
        tur: DugumTur.gun,
        x: p.x,
        y: p.y,
        yaricap: (haftaBasi ? 7 : 4) + 2.5 * math.sqrt(liste.length),
        ad: haftaBasi ? haftaEtiketi(g) : '',
        duygu: duygular.isEmpty ? null : duygular.reduce((a, b) => a + b) / duygular.length,
      ),
    );
    if (i > 0) kenarlar.add(Kenar(dugumler[dugumler.length - 2].id, id, agirlik: 0.5));
    // Anlıklar kendi gününün çevresinde küçük noktalar.
    for (var j = 0; j < liste.length; j++) {
      final a = liste[j];
      final aci = 2 * math.pi * j / liste.length - math.pi / 2;
      final mesafe = 14 + 2.5 * math.sqrt(liste.length);
      dugumler.add(
        Dugum(
          id: anlikDugumu(a.id),
          tur: DugumTur.anlik,
          x: p.x + mesafe * math.cos(aci),
          y: p.y + mesafe * math.sin(aci),
          yaricap: 3,
          ad: a.metin,
          duygu: a.duygu?.toDouble(),
          vurgulu: vurgulu.contains(a.id),
        ),
      );
      kenarlar.add(Kenar(id, anlikDugumu(a.id), agirlik: 0.3));
    }
  }
  return GrafVerisi(dugumler, kenarlar);
}

/// "11–17 Kas" (hafta başı düğümünün etiketi).
String haftaEtiketi(DateTime pazartesi) {
  final pazar = pazartesi.add(const Duration(days: 6));
  if (pazartesi.month == pazar.month) return '${pazartesi.day}–${formatDayMonth(pazar)}';
  return '${formatDayMonth(pazartesi)} – ${formatDayMonth(pazar)}';
}

/// Ana etiket: üstü olmayan. Altı katlanır; açık ana etiketin doğrudan altları
/// ayrı düğüm olur (onların altları da onlara katlanır).
GrafVerisi _anaEtiketler(List<Anlik> sirali, Map<String, Etiket> etiketler, List<Bag> baglar, Set<String> acik) {
  final ust = ustHaritasi(baglar);
  final alt = altHaritasi(baglar);
  // Her etiketin görünen temsilcisi: yukarı çıkılır, açık olmayan ilk ana/üst.
  final temsilci = <String, String>{};
  String bul(String id, Set<String> yol) {
    final hazir = temsilci[id];
    if (hazir != null) return hazir;
    final ustler = [
      for (final u in ust[id] ?? const <String>{})
        if (etiketler.containsKey(u) && !yol.contains(u)) u,
    ]..sort();
    if (ustler.isEmpty) return id; // ana etiket
    final u = ustler.first;
    final uTemsil = bul(u, {...yol, u});
    // Üst açık ve temsilcisi kendisiyse bu etiket ayrı görünür.
    final sonuc = (acik.contains(u) && uTemsil == u) ? id : uTemsil;
    return sonuc;
  }

  for (final id in etiketler.keys) {
    temsilci[id] = bul(id, {id});
  }
  final anlikD = _anlikDugumleri(sirali);
  final konum = {for (final d in anlikD) d.id: (x: d.x, y: d.y)};
  final komsular = <String, List<({double x, double y})>>{};
  final sayi = <String, Set<String>>{};
  final kenarAnahtari = <String>{};
  final kenarlar = <Kenar>[];
  for (final b in baglar) {
    if (b.tip != BagTip.etiketli) continue;
    final a = konum[anlikDugumu(b.kaynakId)];
    final t = temsilci[b.hedefId];
    if (a == null || t == null) continue;
    (sayi[t] ??= {}).add(b.kaynakId);
    if (kenarAnahtari.add('${b.kaynakId}|$t')) {
      (komsular[t] ??= []).add(a);
      kenarlar.add(Kenar(anlikDugumu(b.kaynakId), etiketDugumu(t), soluk: b.durum == BagDurum.onerildi));
    }
  }
  final gorunen = temsilci.values.toSet().toList()
    ..sort((a, b) => etiketler[a]!.normAd.compareTo(etiketler[b]!.normAd));
  for (final id in gorunen) {
    for (final u in ust[id] ?? const <String>{}) {
      if (gorunen.contains(u)) kenarlar.add(Kenar(etiketDugumu(id), etiketDugumu(u)));
    }
  }
  final etiketD = <Dugum>[];
  for (var i = 0; i < gorunen.length; i++) {
    final id = gorunen[i];
    final d = _etiketDugumu(
      etiketler[id]!,
      komsular[id] ?? const [],
      i,
      gorunen.length,
      boyut: (sayi[id]?.length ?? 0).toDouble(),
    );
    final katli = !acik.contains(id) && (alt[id] ?? const <String>{}).isNotEmpty;
    etiketD.add(
      Dugum(
        id: d.id,
        tur: d.tur,
        x: d.x,
        y: d.y,
        yaricap: d.yaricap,
        ad: katli ? '${d.ad} +' : d.ad,
        etiket: d.etiket,
        sabit: false,
        katli: katli,
      ),
    );
  }
  return GrafVerisi([...anlikD, ...etiketD], kenarlar);
}

GrafVerisi _etiketAgaci(Map<String, Etiket> etiketler, List<Bag> baglar) {
  final satirlar = etiketAgaci(etiketler.values.toList(), baglar);
  // Ağaç sırası bir sarmala dizilir: ana etiketler ve altları yan yana düşer.
  final sira = <String>[];
  for (final s in satirlar) {
    if (!sira.contains(s.etiket.id)) sira.add(s.etiket.id);
  }
  final anlikSayisi = <String, int>{};
  for (final b in baglar) {
    if (b.tip == BagTip.etiketli) anlikSayisi[b.hedefId] = (anlikSayisi[b.hedefId] ?? 0) + 1;
  }
  final dugumler = <Dugum>[];
  for (var i = 0; i < sira.length; i++) {
    final p = sarmalNoktasi(sira.length <= 1 ? 0 : i / (sira.length - 1), r0: sarmalR * 0.8);
    final e = etiketler[sira[i]]!;
    dugumler.add(
      Dugum(
        id: etiketDugumu(e.id),
        tur: DugumTur.etiket,
        x: p.x,
        y: p.y,
        yaricap: 8 + 3 * math.sqrt(anlikSayisi[e.id] ?? 0),
        ad: e.ad,
        etiket: e,
        sabit: false,
      ),
    );
  }
  final kenarlar = [
    for (final b in baglar)
      if (b.tip == BagTip.ust && etiketler.containsKey(b.kaynakId) && etiketler.containsKey(b.hedefId))
        Kenar(etiketDugumu(b.kaynakId), etiketDugumu(b.hedefId), soluk: b.durum == BagDurum.onerildi),
  ];
  return GrafVerisi(dugumler, kenarlar);
}

/// Etikete uzun basınca vurgulanacaklar: kendisi ve doğrudan komşuları.
Set<String> komsular(GrafVerisi g, String dugumId) => {
  dugumId,
  for (final k in g.kenarlar)
    if (k.a == dugumId) k.b else if (k.b == dugumId) k.a,
};
