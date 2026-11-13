// Anlık araması (saf Dart): kutu metinde ve etiket adlarında arar (etiket
// 1.0, metin 0.7; yazım hatasına dayanıklı, soru defteriyle aynı parçalar).
//
// Kısa yazım: `#his` etiket filtresi ekler, `-#ders` dışlar, `((his))` da
// `#his` gibidir. Filtreler: etiket(ler) (hepsi / herhangi; alt etiketleri
// kapsar), tarih aralığı, duygu aralığı, etiketin geldiği yer, etiketsizler.
import '../../../core/text/fuzzy_search.dart';
import '../../../core/text/turkish_text.dart';
import 'anlik.dart';
import 'etiket_kurallari.dart';

const etiketAgirligi = 1.0;
const metinAgirligi = 0.7;

/// Kutudan çözülen arama: serbest metin ve kısa yazımla gelen etiket adları.
class AnlikSorgusu {
  const AnlikSorgusu({this.metin = '', this.dahil = const {}, this.haric = const {}});
  final String metin;

  /// Normalize etiket adları.
  final Set<String> dahil;
  final Set<String> haric;
}

/// `#his`, `-#ders`, `((his))` ve serbest metin.
AnlikSorgusu sorguCoz(String kutu) {
  final dahil = <String>{}, haric = <String>{};
  var kalan = kutu.replaceAllMapped(RegExp(r'(-?)\(\(([^()\n]{1,40})\)\)'), (m) {
    final n = normalizeTr(m.group(2)!);
    if (n.isNotEmpty) (m.group(1) == '-' ? haric : dahil).add(n);
    return ' ';
  });
  kalan = kalan.replaceAllMapped(RegExp(r'(^|\s)(-?)#([^\s#]+)'), (m) {
    final n = normalizeTr(m.group(3)!.replaceAll('_', ' '));
    if (n.isNotEmpty) (m.group(2) == '-' ? haric : dahil).add(n);
    return ' ';
  });
  return AnlikSorgusu(metin: kalan.replaceAll(RegExp(r'\s+'), ' ').trim(), dahil: dahil, haric: haric);
}

enum EtiketModu { hepsi, herhangi }

class AnlikFiltresi {
  const AnlikFiltresi({
    this.etiketler = const {},
    this.mod = EtiketModu.hepsi,
    this.baslangic,
    this.bitis,
    this.duyguEnAz,
    this.duyguEnCok,
    this.nedenler = const {},
    this.etiketsiz = false,
  });

  /// Seçili etiket kimlikleri (alt etiketleri de kapsar).
  final Set<String> etiketler;
  final EtiketModu mod;

  /// Gün olarak; ikisi de dahil.
  final DateTime? baslangic;
  final DateTime? bitis;

  /// Duygu aralığı; biri doluysa duygusu boş olan anlıklar elenir.
  final int? duyguEnAz;
  final int? duyguEnCok;

  /// Etiketin geldiği yer: metin içi, şerit, yapay zekâ.
  final Set<BagNeden> nedenler;
  final bool etiketsiz;

  bool get bos =>
      etiketler.isEmpty &&
      baslangic == null &&
      bitis == null &&
      duyguEnAz == null &&
      duyguEnCok == null &&
      nedenler.isEmpty &&
      !etiketsiz;

  AnlikFiltresi kopya({
    Set<String>? etiketler,
    EtiketModu? mod,
    DateTime? Function()? baslangic,
    DateTime? Function()? bitis,
    int? Function()? duyguEnAz,
    int? Function()? duyguEnCok,
    Set<BagNeden>? nedenler,
    bool? etiketsiz,
  }) => AnlikFiltresi(
    etiketler: etiketler ?? this.etiketler,
    mod: mod ?? this.mod,
    baslangic: baslangic == null ? this.baslangic : baslangic(),
    bitis: bitis == null ? this.bitis : bitis(),
    duyguEnAz: duyguEnAz == null ? this.duyguEnAz : duyguEnAz(),
    duyguEnCok: duyguEnCok == null ? this.duyguEnCok : duyguEnCok(),
    nedenler: nedenler ?? this.nedenler,
    etiketsiz: etiketsiz ?? this.etiketsiz,
  );
}

/// Arama sonucu: anlıklar alaka sırasına göre (metin yoksa yeniden eskiye).
/// Bilinmeyen `#ad` hiçbir anlıkla eşleşmez (boş sonuç, hata değil).
List<Anlik> anlikAra({
  required List<Anlik> anliklar,
  required List<Etiket> etiketler,
  required List<Bag> baglar,
  String kutu = '',
  AnlikFiltresi filtre = const AnlikFiltresi(),
}) {
  final sorgu = sorguCoz(kutu);
  final adla = {
    for (final e in etiketler)
      if (!e.silindi) e.normAd: e,
  };
  final kimlikle = {
    for (final e in etiketler)
      if (!e.silindi) e.id: e,
  };

  // Her anlığın etkin etiket bağları.
  final anlikBaglari = <String, List<Bag>>{};
  for (final b in baglar) {
    if (b.tip == BagTip.etiketli && b.etkin && kimlikle.containsKey(b.hedefId)) {
      (anlikBaglari[b.kaynakId] ??= []).add(b);
    }
  }
  Set<String> etiketleri(String anlikId) => {for (final b in anlikBaglari[anlikId] ?? const <Bag>[]) b.hedefId};

  // İstenen etiket grupları: her grup bir etiket ve alt etiketleri.
  final gruplar = <Set<String>>[
    for (final id in filtre.etiketler) altlariylaBirlikte(id, baglar),
    for (final n in sorgu.dahil) adla[n] == null ? <String>{} : altlariylaBirlikte(adla[n]!.id, baglar),
  ];
  final haric = <String>{
    for (final n in sorgu.haric)
      if (adla[n] != null) ...altlariylaBirlikte(adla[n]!.id, baglar),
  };
  // Kutuda #etiket yazıldıysa hepsi aranır; yoksa filtredeki mod geçerli.
  final hepsi = filtre.mod == EtiketModu.hepsi || sorgu.dahil.isNotEmpty;

  final qs = searchTokens(sorgu.metin);
  final normQuery = normalizeTr(sorgu.metin);
  final puanli = <(Anlik, double)>[];
  for (final a in anliklar) {
    if (a.silindi) continue;
    final ets = etiketleri(a.id);
    if (gruplar.isNotEmpty) {
      bool tutar(Set<String> g) => g.any(ets.contains);
      if (!(hepsi ? gruplar.every(tutar) : gruplar.any(tutar))) continue;
    }
    if (ets.any(haric.contains)) continue;
    if (filtre.etiketsiz && ets.isNotEmpty) continue;
    if (filtre.nedenler.isNotEmpty &&
        !(anlikBaglari[a.id] ?? const <Bag>[]).any((b) => filtre.nedenler.contains(b.neden))) {
      continue;
    }
    final gun = DateTime(a.olusturma.year, a.olusturma.month, a.olusturma.day);
    if (filtre.baslangic != null && gun.isBefore(_gunu(filtre.baslangic!))) continue;
    if (filtre.bitis != null && gun.isAfter(_gunu(filtre.bitis!))) continue;
    if (filtre.duyguEnAz != null || filtre.duyguEnCok != null) {
      final d = a.duygu;
      if (d == null) continue;
      if (filtre.duyguEnAz != null && d < filtre.duyguEnAz!) continue;
      if (filtre.duyguEnCok != null && d > filtre.duyguEnCok!) continue;
    }
    if (qs.isEmpty) {
      puanli.add((a, 0));
      continue;
    }
    final puan = relevanceScore(
      [for (final id in ets) SearchField(kimlikle[id]!.ad, etiketAgirligi), SearchField(a.metin, metinAgirligi)],
      qs,
      normQuery,
    );
    if (puan != null) puanli.add((a, puan));
  }
  puanli.sort((x, y) {
    final p = y.$2.compareTo(x.$2);
    return p != 0 ? p : y.$1.olusturma.compareTo(x.$1.olusturma);
  });
  return [for (final (a, _) in puanli) a];
}

DateTime _gunu(DateTime d) => DateTime(d.year, d.month, d.day);
