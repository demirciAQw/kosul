// Metin içi etiket: `((selam))` "selam" etiketine bağdır.
//
// Burada sadece metinle ilgili saf kurallar var: ((…)) bulma, yazarken
// imlecin bir ((… içinde olup olmadığı, etiket adı düzeltme, metinde bir
// etiketi düz yazıya çevirme ve yeniden adlandırma. Testler: test/anlik_test.dart.
import '../../../core/text/turkish_text.dart';

/// Metinde bulunan bir `((ad))`. [bas] `((`'nin, [son] `))`'den sonraki konum.
class EtiketAtfi {
  const EtiketAtfi(this.ad, this.bas, this.son);
  final String ad;
  final int bas;
  final int son;

  String get normAd => normalizeTr(ad);
}

/// Etiket adı: baştaki/sondaki boşluk atılır, aradaki boşluklar teke iner.
String etiketAdiDuzelt(String ad) => ad.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Ad etiket olabilir mi? Boş ya da sadece noktalama olamaz; satır ve parantez içeremez.
bool gecerliEtiketAdi(String ad) =>
    !ad.contains('\n') &&
    !ad.contains('(') &&
    !ad.contains(')') &&
    normalizeTr(etiketAdiDuzelt(ad)).isNotEmpty &&
    etiketAdiDuzelt(ad).length <= 40;

/// Metindeki bütün `((…))` etiketleri, sırayla.
///
/// Kurallar: iç içe yazılırsa en içteki alınır (`((a ((b)) c))` → b);
/// kapanmamış `((abc` etiket değildir; boş `(( ))` ve satır atlayan içerik
/// atlanır; 40 harften uzun içerik etiket sayılmaz.
List<EtiketAtfi> metinEtiketleri(String metin) {
  final sonuc = <EtiketAtfi>[];
  var i = 0;
  while (true) {
    final bas = metin.indexOf('((', i);
    if (bas < 0) break;
    final kapanis = metin.indexOf('))', bas + 2);
    if (kapanis < 0) break;
    final ic = metin.indexOf('((', bas + 1);
    if (ic >= 0 && ic < kapanis) {
      i = ic; // daha içte bir açılış var: oradan başla
      continue;
    }
    final ham = metin.substring(bas + 2, kapanis);
    if (gecerliEtiketAdi(ham)) {
      sonuc.add(EtiketAtfi(etiketAdiDuzelt(ham), bas, kapanis + 2));
    }
    i = kapanis + 2;
  }
  return sonuc;
}

/// Metindeki etiketlerin normalize adları (tekrarsız).
Set<String> metinEtiketAdlari(String metin) => {for (final a in metinEtiketleri(metin)) a.normAd};

/// Yazarken imleç açık bir `((…` içinde mi? Öyleyse yazılan kısım ve `((`'nin
/// konumu döner (öneri listesi bununla süzülür). Değilse null.
({String sorgu, int bas})? acikEtiket(String metin, int imlec) {
  if (imlec < 2 || imlec > metin.length) return null;
  final once = metin.substring(0, imlec);
  final bas = once.lastIndexOf('((');
  if (bas < 0) return null;
  final yazilan = once.substring(bas + 2);
  if (yazilan.contains('))') || yazilan.contains('\n') || yazilan.contains('(') || yazilan.length > 40) {
    return null;
  }
  return (sorgu: yazilan, bas: bas);
}

/// Öneri seçilince: imleçteki açık `((yazılan` kısmı `((ad))` olur.
/// Döner: yeni metin ve imlecin yeni yeri (kapanıştan sonra, bir boşlukla).
({String metin, int imlec}) etiketiTamamla(String metin, int imlec, String ad) {
  final acik = acikEtiket(metin, imlec);
  if (acik == null) return (metin: metin, imlec: imlec);
  var sonrasi = metin.substring(imlec);
  // İmleçten sonra hemen "))" varsa (önceden kapatılmışsa) onu da yut.
  final kapanis = RegExp(r'^[^()\n]{0,40}\)\)').firstMatch(sonrasi);
  if (kapanis != null) sonrasi = sonrasi.substring(kapanis.end);
  final ek = '(($ad))';
  final bosluk = sonrasi.startsWith(' ') ? '' : ' ';
  final yeni = metin.substring(0, acik.bas) + ek + bosluk + sonrasi;
  return (metin: yeni, imlec: acik.bas + ek.length + bosluk.length);
}

/// `((ad))` yazılarını düz yazıya çevirir (etiket silinince). Sadece normalize
/// adı [normAd] olanlar değişir.
String etiketiDuzYaziYap(String metin, String normAd) => _degistir(metin, normAd, (a) => a.ad);

/// `((eski))` → `((yeni))` (yeniden adlandırma).
String etiketiYenidenAdlandir(String metin, String eskiNormAd, String yeniAd) =>
    _degistir(metin, eskiNormAd, (_) => '(($yeniAd))');

String _degistir(String metin, String normAd, String Function(EtiketAtfi) yerine) {
  final atiflar = metinEtiketleri(metin).where((a) => a.normAd == normAd).toList();
  if (atiflar.isEmpty) return metin;
  final b = StringBuffer();
  var i = 0;
  for (final a in atiflar) {
    b
      ..write(metin.substring(i, a.bas))
      ..write(yerine(a));
    i = a.son;
  }
  b.write(metin.substring(i));
  return b.toString();
}
