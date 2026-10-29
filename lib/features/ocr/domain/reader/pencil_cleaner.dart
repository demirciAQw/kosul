import 'dart:math' as math;
import 'dart:typed_data';

import '../question_text.dart';

/// Kurşun kalem ve renkli kalem izlerini okumadan önce siler.
///
/// Basılı yazının koyu bir çekirdeği vardır; kalem izleri genellikle daha açık
/// ve basılı yazıdan uzaktadır. Arka plana göre koyuluk ölçülür; eşik her
/// fotoğrafın kendi dağılımından seçilir (en koyu %1'in %70'i, en az 45).
/// Koyu çekirdeğe 2 pikselden yakın her şey (harf kenarları) korunur; uzaktaki
/// izler o bölgenin kâğıt rengiyle doldurulur (beyaz "hayalet" çizgi kalmaz).
///
/// Asıl fotoğrafın okuması her zaman temeldir; temizlenmiş görüntüden yalnızca
/// asılda okunamayan yerler eklenir ([mergeOcrLines]). Örnek fotoğraflarda
/// (Tesseract ile) asıl okuma korunup +14 ile +28 kelime kazanıldı.
class PencilJob {
  const PencilJob(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width, height;
}

/// `compute` için üst düzey giriş.
Uint8List cleanPencilTask(PencilJob job) => cleanPencil(job.rgba, job.width, job.height);

Float64List _boxMean(Float64List a, int w, int h, int r) {
  final integ = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0.0;
    for (var x = 0; x < w; x++) {
      row += a[y * w + x];
      integ[(y + 1) * (w + 1) + x + 1] = integ[y * (w + 1) + x + 1] + row;
    }
  }
  final out = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max<int>(0, y - r), y1 = math.min<int>(h, y + r + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max<int>(0, x - r), x1 = math.min<int>(w, x + r + 1);
      final s = integ[y1 * (w + 1) + x1] - integ[y0 * (w + 1) + x1] - integ[y1 * (w + 1) + x0] + integ[y0 * (w + 1) + x0];
      out[y * w + x] = s / ((y1 - y0) * (x1 - x0));
    }
  }
  return out;
}

/// Temizlenmiş RGBA kopyası (girdi değişmez).
Uint8List cleanPencil(Uint8List rgba, int w, int h) {
  final n = w * h;
  final lum = Float64List(n);
  for (var i = 0; i < n; i++) {
    lum[i] = 0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2];
  }
  final bg = _boxMean(lum, w, h, 25);

  // Koyuluk dağılımı (yalnızca mürekkep): eşik en koyu %1'in %70'i, en az 45.
  final hist = List<int>.filled(256, 0);
  var inkCount = 0;
  for (var i = 0; i < n; i++) {
    final c = bg[i] - lum[i];
    if (c > 25) {
      hist[math.min<int>(255, c.floor())]++;
      inkCount++;
    }
  }
  if (inkCount == 0) return Uint8List.fromList(rgba);
  var p99 = 255;
  var seen = 0;
  for (var v = 255; v >= 0; v--) {
    seen += hist[v];
    if (seen >= inkCount * 0.01) {
      p99 = v;
      break;
    }
  }
  final darkT = math.max<double>(45, 0.7 * p99);

  final dark = Float64List(n);
  for (var i = 0; i < n; i++) {
    if (bg[i] - lum[i] > darkT) dark[i] = 1;
  }
  final nearDark = _boxMean(dark, w, h, 2);

  final out = Uint8List.fromList(rgba);
  for (var i = 0; i < n; i++) {
    if (bg[i] - lum[i] > 25 && nearDark[i] <= 0) {
      final r = bg[i].round();
      final v = r < 0 ? 0 : (r > 255 ? 255 : r);
      out[i * 4] = v;
      out[i * 4 + 1] = v;
      out[i * 4 + 2] = v;
      out[i * 4 + 3] = 255;
    }
  }
  return out;
}

/// Asıl okuma temel. Temizlenmiş okumadan:
/// - asılda karşılığı olmayan (kutusu güvenilir bir satırla %30'dan fazla
///   örtüşmeyen) ve en az iki harf/rakam içeren satırlar eklenir;
/// - asıldaki bir satırla aynı yere düşen (%50'den fazla örtüşen) ve güveni en
///   az 0,15 yüksek olan satır, asıldaki bozuk okumanın yerini alır (ör. kalem
///   izi yüzünden "NA gönderme" → "salgılar gönderme").
/// ML Kit güven vermezse (hepsi 1) yer değiştirme olmaz.
List<OcrLine> mergeOcrLines(List<OcrLine> base, List<OcrLine> extra) {
  double overlap(OcrLine a, OcrLine b) {
    final aw = a.width > 0 ? a.width : a.text.length * a.height * 0.5;
    final bw = b.width > 0 ? b.width : b.text.length * b.height * 0.5;
    final ix = math.max<double>(0, math.min<double>(a.left + aw, b.left + bw) - math.max<double>(a.left, b.left));
    final iy = math.max<double>(0, math.min<double>(a.top + a.height, b.top + b.height) - math.max<double>(a.top, b.top));
    final smaller = math.min<double>(aw * a.height, bw * b.height);
    return smaller <= 0 ? 0 : ix * iy / smaller;
  }

  final alnum = RegExp(r'[0-9A-Za-zÇĞİÖŞÜçğıöşü]');
  bool meaningful(OcrLine l) => alnum.allMatches(l.text).length >= 2;
  final used = <OcrLine>{};
  final merged = [
    for (final b in base)
      () {
        final better = extra
            .where((e) =>
                !used.contains(e) && meaningful(e) && e.confidence >= b.confidence + 0.15 && overlap(e, b) > 0.5)
            .fold<OcrLine?>(null, (best, e) => best == null || e.confidence > best.confidence ? e : best);
        if (better == null) return b;
        used.add(better);
        return better;
      }(),
  ];
  final trusted = [for (final l in merged) if (l.confidence >= 0.5) l];
  return [
    ...merged,
    for (final e in extra)
      if (!used.contains(e) && meaningful(e) && !trusted.any((b) => overlap(e, b) > 0.3)) e,
  ];
}
