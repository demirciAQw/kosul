// Anlık, etiket ve bağın eşitleme biçimi (JSON) ve iki küçük kural:
// aynı normalize adlı etiketlerin birleştirilmesi ve Obsidian'daki
// `Anlar/*.md` dosyalarının okunması (tek seferlik içe aktarma).
//
// Alan adları koc-arac tarafında da aynıdır (sunucu kayıtları olduğu gibi saklar).
import '../../../core/text/turkish_text.dart';
import 'anlik.dart';
import 'etiket_metni.dart';

String _z(DateTime d) => d.toUtc().toIso8601String();
DateTime _t(Object? s, DateTime yedek) => DateTime.tryParse('${s ?? ''}')?.toLocal() ?? yedek;

Map<String, Object?> anlikJson(Anlik a) => {
  'id': a.id,
  'metin': a.metin,
  'olusturma': _z(a.olusturma),
  'guncelleme': _z(a.guncelleme),
  'duygu': a.duygu,
  'cihaz': a.cihaz,
  'silindi': a.silindi,
};

Map<String, Object?> etiketJson(Etiket e) => {
  'id': e.id,
  'ad': e.ad,
  'normAd': e.normAd,
  'tur': e.tur.name,
  'renk': e.renk,
  'olusturan': e.olusturan,
  'olusturma': _z(e.olusturma),
  'guncelleme': _z(e.guncelleme),
  'silindi': e.silindi,
};

Map<String, Object?> bagJson(Bag b) => {
  'id': b.id,
  'tip': b.tip.name,
  'kaynakTur': b.kaynakTur.name,
  'kaynakId': b.kaynakId,
  'hedefTur': b.hedefTur.name,
  'hedefId': b.hedefId,
  'neden': b.neden.name,
  'durum': b.durum.name,
  'puan': b.puan,
  'olusturma': _z(b.olusturma),
  'guncelleme': _z(b.guncelleme),
  'silindi': b.silindi,
};

/// Bozuk kayıt null döner (atlanır, uygulama çökmez).
Anlik? anlikOku(Map<String, Object?> j, DateTime simdi) {
  final id = j['id'], metin = j['metin'];
  if (id is! String || id.isEmpty || metin is! String) return null;
  final duygu = j['duygu'];
  return Anlik(
    id: id,
    metin: metin,
    olusturma: _t(j['olusturma'], simdi),
    guncelleme: _t(j['guncelleme'], simdi),
    duygu: duygu is int && duygu >= -3 && duygu <= 3 ? duygu : null,
    cihaz: j['cihaz'] as String? ?? '',
    silindi: j['silindi'] == true,
    esitlenmedi: false,
  );
}

Etiket? etiketOku(Map<String, Object?> j, DateTime simdi) {
  final id = j['id'], ad = j['ad'];
  if (id is! String || id.isEmpty || ad is! String || normalizeTr(ad).isEmpty) return null;
  final renk = j['renk'];
  return Etiket(
    id: id,
    ad: etiketAdiDuzelt(ad),
    normAd: normalizeTr(ad),
    tur: EtiketTur.coz(j['tur']),
    renk: renk is int ? renk : null,
    olusturan: j['olusturan'] == 'ai' ? 'ai' : 'ben',
    olusturma: _t(j['olusturma'], simdi),
    guncelleme: _t(j['guncelleme'], simdi),
    silindi: j['silindi'] == true,
    esitlenmedi: false,
  );
}

Bag? bagOku(Map<String, Object?> j, DateTime simdi) {
  final id = j['id'], k = j['kaynakId'], h = j['hedefId'];
  if (id is! String || id.isEmpty || k is! String || h is! String) return null;
  final puan = j['puan'];
  return Bag(
    id: id,
    tip: BagTip.coz(j['tip']),
    kaynakTur: UcTur.coz(j['kaynakTur']),
    kaynakId: k,
    hedefTur: UcTur.coz(j['hedefTur']),
    hedefId: h,
    neden: BagNeden.coz(j['neden']),
    durum: BagDurum.coz(j['durum']),
    puan: puan is num ? puan.toDouble() : null,
    olusturma: _t(j['olusturma'], simdi),
    guncelleme: _t(j['guncelleme'], simdi),
    silindi: j['silindi'] == true,
    esitlenmedi: false,
  );
}

/// Aynı normalize ada sahip etiketler birleştirilir: en eski (olusturma, sonra
/// kimlik) kalır. Döner: kaybeden kimlik → kalan kimlik. Kaybedenin bağları
/// kalana taşınır, kendisi yumuşak silinir (iki tarafta da aynı sonuç çıkar).
Map<String, String> etiketBirlestirmeHaritasi(List<Etiket> etiketler) {
  final gruplar = <String, List<Etiket>>{};
  for (final e in etiketler) {
    if (!e.silindi) (gruplar[e.normAd] ??= []).add(e);
  }
  final harita = <String, String>{};
  for (final g in gruplar.values) {
    if (g.length < 2) continue;
    g.sort((a, b) {
      final c = a.olusturma.compareTo(b.olusturma);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    for (final e in g.skip(1)) {
      harita[e.id] = g.first.id;
    }
  }
  return harita;
}

// ───────────────────────── Anlar/*.md içe aktarma ─────────────────────────

/// Obsidian notu: ön bilgideki `zaman` (ya da `tarih`) tarih olur; metin ve
/// ((…)) korunur. Ön bilgi yoksa ya da tarih okunamazsa [dosyaZamani] kullanılır.
({DateTime zaman, String metin, int? duygu})? mdAnlikOku(String icerik, DateTime dosyaZamani) {
  var metin = icerik.replaceAll('\r\n', '\n');
  DateTime? zaman;
  int? duygu;
  final on = RegExp(r'^---\n([\s\S]*?)\n---\n?').firstMatch(metin);
  if (on != null) {
    for (final satir in on.group(1)!.split('\n')) {
      final i = satir.indexOf(':');
      if (i < 0) continue;
      final anahtar = satir.substring(0, i).trim().toLowerCase();
      final deger = satir.substring(i + 1).trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
      if (anahtar == 'zaman' || anahtar == 'tarih') {
        zaman ??= DateTime.tryParse(deger.replaceFirst(' ', 'T'));
      } else if (anahtar == 'duygu') {
        final d = int.tryParse(deger);
        if (d != null && d >= -3 && d <= 3) duygu = d;
      }
    }
    metin = metin.substring(on.end);
  }
  metin = metin.trim();
  if (metin.isEmpty) return null;
  return (zaman: zaman ?? dosyaZamani, metin: metin, duygu: duygu);
}

/// İçe aktarılan dosyanın kalıcı kimliği: aynı dosya iki kez aktarılırsa çift kayıt olmaz.
String mdAnlikId(String dosyaAdi) =>
    'md-${normalizeTr(dosyaAdi.replaceAll(RegExp(r'\.md$'), '')).replaceAll(' ', '-')}';
