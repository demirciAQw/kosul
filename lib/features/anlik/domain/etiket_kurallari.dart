// Etiket ve bağ kuralları (saf Dart, veritabanı yok).
//
// - metin bağlarının yeniden hesabı (kayıtta ((…)) değişince)
// - öneri sırası (son 7 gün, sonra en çok kullanılan)
// - alt-üst ağacı, döngü engeli, alt etiketler
// - etiket şeridi (metinden gelenler çerçeveli, kaldırılamaz)
// - etiket silme planı (sadece bu / alt etiketleriyle)
import '../../../core/text/turkish_text.dart';
import 'anlik.dart';
import 'etiket_metni.dart';

// ───────────────────────── Metin bağları ─────────────────────────

/// Anlık kaydedilince `neden=metin` bağları yeniden hesaplanır. Şerit, elle
/// ve yapay zekâ bağlarına dokunulmaz.
///
/// [metindekiler]: metindeki etiketlerin kimlikleri (adı bilinen etiketler).
/// [mevcut]: bu anlığın bütün `etiketli` bağları (silinmişler dahil).
/// Döner: eklenecek etiket kimlikleri, geri getirilecek (silinmiş) bağlar ve
/// yumuşak silinecek bağlar.
({Set<String> ekle, List<Bag> geriGetir, List<Bag> sil}) metinBagFarki({
  required Set<String> metindekiler,
  required List<Bag> mevcut,
}) {
  final metinBaglari = mevcut.where((b) => b.tip == BagTip.etiketli && b.neden == BagNeden.metin).toList();
  final etkin = {
    for (final b in metinBaglari)
      if (!b.silindi) b.hedefId,
  };
  final sil = [
    for (final b in metinBaglari)
      if (!b.silindi && !metindekiler.contains(b.hedefId)) b,
  ];
  final geriGetir = <Bag>[];
  final ekle = <String>{};
  for (final id in metindekiler) {
    if (etkin.contains(id)) continue;
    final eski = metinBaglari.where((b) => b.silindi && b.hedefId == id).firstOrNull;
    if (eski != null) {
      geriGetir.add(eski);
    } else {
      ekle.add(id);
    }
  }
  return (ekle: ekle, geriGetir: geriGetir, sil: sil);
}

// ───────────────────────── Öneri sırası ─────────────────────────

/// `((` yazınca ve `+` listesinde gösterilecek etiketler.
///
/// Önce son 7 günde kullanılanlar (en yenisi önce), sonra en çok
/// kullanılanlar, sonra ada göre. [sorgu] normalizeTr ile süzülür: başında
/// geçenler, içinde geçenlerden önce gelir.
List<Etiket> etiketOnerileri({
  required List<Etiket> etiketler,
  required List<Bag> baglar,
  required Map<String, DateTime> anlikZamanlari,
  required DateTime simdi,
  String sorgu = '',
}) {
  final q = normalizeTr(sorgu);
  final sonKullanim = <String, DateTime>{};
  final sayi = <String, int>{};
  for (final b in baglar) {
    if (!b.etkin || b.tip != BagTip.etiketli) continue;
    final z = anlikZamanlari[b.kaynakId];
    if (z == null) continue;
    sayi[b.hedefId] = (sayi[b.hedefId] ?? 0) + 1;
    final onceki = sonKullanim[b.hedefId];
    if (onceki == null || z.isAfter(onceki)) sonKullanim[b.hedefId] = z;
  }
  final sinir = simdi.subtract(const Duration(days: 7));
  int grup(Etiket e) => q.isEmpty || e.normAd.startsWith(q) ? 0 : 1;
  final aday = [
    for (final e in etiketler)
      if (!e.silindi && (q.isEmpty || e.normAd.contains(q))) e,
  ];
  aday.sort((a, b) {
    final g = grup(a).compareTo(grup(b));
    if (g != 0) return g;
    final za = sonKullanim[a.id], zb = sonKullanim[b.id];
    final ya = za != null && za.isAfter(sinir), yb = zb != null && zb.isAfter(sinir);
    if (ya != yb) return ya ? -1 : 1;
    if (ya && yb) return zb.compareTo(za);
    final s = (sayi[b.id] ?? 0).compareTo(sayi[a.id] ?? 0);
    if (s != 0) return s;
    return a.normAd.compareTo(b.normAd);
  });
  return aday;
}

/// Aranan ad hiçbir etiketle birebir eşleşmiyorsa "yeni etiket" seçeneği gösterilir.
bool yeniEtiketGosterilsinMi(List<Etiket> etiketler, String sorgu) {
  final q = normalizeTr(sorgu);
  return q.isNotEmpty && gecerliEtiketAdi(sorgu) && !etiketler.any((e) => !e.silindi && e.normAd == q);
}

/// Aynı normalize ada sahip silinmemiş etiket (yoksa null).
Etiket? adlaBul(List<Etiket> etiketler, String ad) {
  final n = normalizeTr(ad);
  return etiketler.where((e) => !e.silindi && e.normAd == n).firstOrNull;
}

// ───────────────────────── Alt-üst ağacı ─────────────────────────

/// Etkin `ust` bağları: alt etiket kimliği → üst etiket kimlikleri.
Map<String, Set<String>> ustHaritasi(List<Bag> baglar) {
  final m = <String, Set<String>>{};
  for (final b in baglar) {
    if (b.tip == BagTip.ust && b.etkin) (m[b.kaynakId] ??= {}).add(b.hedefId);
  }
  return m;
}

/// Üst etiket kimliği → doğrudan alt etiket kimlikleri.
Map<String, Set<String>> altHaritasi(List<Bag> baglar) {
  final m = <String, Set<String>>{};
  for (final b in baglar) {
    if (b.tip == BagTip.ust && b.etkin) (m[b.hedefId] ??= {}).add(b.kaynakId);
  }
  return m;
}

/// [id] ve bütün alt etiketleri (torunlar dahil).
Set<String> altlariylaBirlikte(String id, List<Bag> baglar) {
  final alt = altHaritasi(baglar);
  final sonuc = <String>{id};
  final yigin = [id];
  while (yigin.isNotEmpty) {
    for (final a in alt[yigin.removeLast()] ?? const <String>{}) {
      if (sonuc.add(a)) yigin.add(a);
    }
  }
  return sonuc;
}

/// [altId] → [ustId] bağı döngü yaratır mı? (kendisi ya da kendi altı üst olamaz)
bool donguOlurMu({required String altId, required String ustId, required List<Bag> baglar}) =>
    altlariylaBirlikte(altId, baglar).contains(ustId);

/// Ana etiket: üstü olmayan etiket.
bool anaEtiketMi(String id, List<Bag> baglar) => (ustHaritasi(baglar)[id] ?? const {}).isEmpty;

/// Ağaç görünümü için sıralı satırlar: ana etiketler başlık, altları girintili.
/// Birden çok üstü olan etiket her üstünün altında görünür.
List<({Etiket etiket, int derinlik})> etiketAgaci(List<Etiket> etiketler, List<Bag> baglar) {
  final etkin = {
    for (final e in etiketler)
      if (!e.silindi) e.id: e,
  };
  final alt = altHaritasi(baglar);
  final ust = ustHaritasi(baglar);
  int sira(String a, String b) => etkin[a]!.normAd.compareTo(etkin[b]!.normAd);
  final satirlar = <({Etiket etiket, int derinlik})>[];
  void gez(String id, int derinlik, Set<String> yol) {
    satirlar.add((etiket: etkin[id]!, derinlik: derinlik));
    final cocuklar = [
      for (final c in alt[id] ?? const <String>{})
        if (etkin.containsKey(c) && !yol.contains(c)) c,
    ]..sort(sira);
    for (final c in cocuklar) {
      gez(c, derinlik + 1, {...yol, c});
    }
  }

  final kokler = [
    for (final id in etkin.keys)
      if ((ust[id] ?? const <String>{}).where(etkin.containsKey).isEmpty) id,
  ]..sort(sira);
  for (final k in kokler) {
    gez(k, 0, {k});
  }
  return satirlar;
}

// ───────────────────────── Etiket şeridi ─────────────────────────

/// Şeritteki bir çip. [metinden]: metinde geçiyor (çerçeveli, şeritten kaldırılamaz).
class SeritCipi {
  const SeritCipi(this.etiket, {required this.metinden, this.bag});
  final Etiket etiket;
  final bool metinden;

  /// Şerit bağı (varsa); çipteki × bunu yumuşak siler.
  final Bag? bag;
}

/// Bir anlığın şeridi: metindeki etiketler (çerçeveli) ve metin dışı bağlar.
/// [seritteSecilenler]: henüz kaydedilmemiş yazma alanında eklenen etiketler.
List<SeritCipi> seritCipleri({
  required String metin,
  required List<Etiket> etiketler,
  List<Bag> anlikBaglari = const [],
  Set<String> seritteSecilenler = const {},
}) {
  final adla = {
    for (final e in etiketler)
      if (!e.silindi) e.normAd: e,
  };
  final kimlikle = {
    for (final e in etiketler)
      if (!e.silindi) e.id: e,
  };
  final ciplar = <SeritCipi>[];
  final gorulen = <String>{};
  for (final n in metinEtiketAdlari(metin)) {
    final e = adla[n];
    if (e != null && gorulen.add(e.id)) ciplar.add(SeritCipi(e, metinden: true));
  }
  for (final b in anlikBaglari) {
    if (b.tip != BagTip.etiketli || !b.etkin || b.neden == BagNeden.metin) continue;
    final e = kimlikle[b.hedefId];
    if (e != null && gorulen.add(e.id)) ciplar.add(SeritCipi(e, metinden: false, bag: b));
  }
  for (final id in seritteSecilenler) {
    final e = kimlikle[id];
    if (e != null && gorulen.add(e.id)) ciplar.add(SeritCipi(e, metinden: false));
  }
  return ciplar;
}

// ───────────────────────── Etiket silme ─────────────────────────

class EtiketSilmePlani {
  const EtiketSilmePlani({
    required this.etiketler,
    required this.baglar,
    required this.metniDegisenler,
    required this.anlikSayisi,
    required this.altSayisi,
  });

  /// Yumuşak silinecek etiket kimlikleri.
  final Set<String> etiketler;

  /// Yumuşak silinecek bağ kimlikleri (silinen etiketlere değen hepsi).
  final Set<String> baglar;

  /// Metni değişecek anlıklar: kimlik → yeni metin (((his)) → his).
  final Map<String, String> metniDegisenler;

  /// "his 14 anlıkta, 3 alt etikette" için sayılar.
  final int anlikSayisi;
  final int altSayisi;
}

/// Etiket silinince ne olur? Anlıklar silinmez. [altlariyla] false ise alt
/// etiketler kalır ve (başka üstleri yoksa) ana etiket olur.
EtiketSilmePlani etiketSilmePlani({
  required String etiketId,
  required bool altlariyla,
  required List<Etiket> etiketler,
  required List<Bag> baglar,
  required List<Anlik> anliklar,
}) {
  final tumAltlar = altlariylaBirlikte(etiketId, baglar);
  final silinecek = altlariyla ? tumAltlar : {etiketId};
  final bagSil = {
    for (final b in baglar)
      if (!b.silindi &&
          ((b.hedefTur == UcTur.etiket && silinecek.contains(b.hedefId)) ||
              (b.kaynakTur == UcTur.etiket && silinecek.contains(b.kaynakId))))
        b.id,
  };
  final normAdlar = {
    for (final e in etiketler)
      if (silinecek.contains(e.id)) e.normAd,
  };
  final metin = <String, String>{};
  for (final a in anliklar) {
    if (a.silindi) continue;
    var yeni = a.metin;
    for (final n in normAdlar) {
      yeni = etiketiDuzYaziYap(yeni, n);
    }
    if (yeni != a.metin) metin[a.id] = yeni;
  }
  final anlikSayisi = {
    for (final b in baglar)
      if (b.etkin && b.tip == BagTip.etiketli && b.hedefId == etiketId) b.kaynakId,
  }.length;
  return EtiketSilmePlani(
    etiketler: silinecek,
    baglar: bagSil,
    metniDegisenler: metin,
    anlikSayisi: anlikSayisi,
    altSayisi: tumAltlar.length - 1,
  );
}

/// Silinmiş ama 30 gün geçmemiş etiketler ("Son silinenler").
List<Etiket> sonSilinenler(List<Etiket> etiketler, DateTime simdi) => [
  for (final e in etiketler)
    if (e.silindi && simdi.difference(e.guncelleme) <= const Duration(days: 30)) e,
]..sort((a, b) => b.guncelleme.compareTo(a.guncelleme));

// ───────────────────────── Etiket sayfası ─────────────────────────

/// Etiketi (ve alt etiketlerini) taşıyan anlıklar, yeniden eskiye.
List<Anlik> etiketinAnliklari({required String etiketId, required List<Anlik> anliklar, required List<Bag> baglar}) {
  final hedefler = altlariylaBirlikte(etiketId, baglar);
  final ids = {
    for (final b in baglar)
      if (b.etkin && b.tip == BagTip.etiketli && hedefler.contains(b.hedefId)) b.kaynakId,
  };
  return [
    for (final a in anliklar)
      if (!a.silindi && ids.contains(a.id)) a,
  ]..sort((a, b) => b.olusturma.compareTo(a.olusturma));
}

// ───────────────────────── Yeniden adlandırma ve birleştirme (v8.6.1) ─────────────────────────

/// Metninde `((ad))` geçen (silinmemiş) anlık kimlikleri: "N anlık etkilenecek".
Set<String> metninde({required String normAd, required List<Anlik> anliklar}) => {
  for (final a in anliklar)
    if (!a.silindi && metinEtiketAdlari(a.metin).contains(normAd)) a.id,
};

/// Aynı iki ucu, aynı tipi ve aynı nedeni olan etkin bağlardan fazlalar
/// (birleştirmeden sonra çift bağ kalmasın). Döner: silinecek bağ kimlikleri;
/// her gruptan en eski kalır.
Set<String> yinelenenBaglar(List<Bag> baglar) {
  final gorulen = <String, Bag>{};
  final sil = <String>{};
  final sirali =
      [
        for (final b in baglar)
          if (!b.silindi) b,
      ]..sort((a, b) {
        final c = a.olusturma.compareTo(b.olusturma);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
  for (final b in sirali) {
    final anahtar = '${b.tip.name}|${b.kaynakId}|${b.hedefId}|${b.neden.name}';
    if (b.kaynakId == b.hedefId || gorulen.containsKey(anahtar)) {
      sil.add(b.id);
    } else {
      gorulen[anahtar] = b;
    }
  }
  return sil;
}

/// [kaynakId] [hedefId]'de toplanırsa alt-üst ağacında döngü oluşur mu?
/// (Kaynağın bir üstü hedefin altındaysa olur.) Kendine bağ sayılmaz, silinir.
bool birlestirmeDonguOlurMu({required String kaynakId, required String hedefId, required List<Bag> baglar}) {
  String cevir(String id) => id == kaynakId ? hedefId : id;
  final ust = <String, Set<String>>{};
  for (final b in baglar) {
    if (b.tip != BagTip.ust || !b.etkin) continue;
    final a = cevir(b.kaynakId), u = cevir(b.hedefId);
    if (a != u) (ust[a] ??= {}).add(u);
  }
  // hedeften yukarı çıkarak hedefe geri dönülüyor mu?
  final gorulen = <String>{};
  final yigin = [...(ust[hedefId] ?? const <String>{})];
  while (yigin.isNotEmpty) {
    final x = yigin.removeLast();
    if (x == hedefId) return true;
    if (gorulen.add(x)) yigin.addAll(ust[x] ?? const {});
  }
  return false;
}
