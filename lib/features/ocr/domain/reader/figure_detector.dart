import 'dart:math' as math;
import 'dart:typed_data';

/// Fotoğraftaki şekil, grafik, tablo ve resimleri bulur ve etiketler.
///
/// Model dosyası gerektirmez (uygulama boyutu büyümez): küçültülmüş görüntüde
/// yerel arka plana göre koyu ya da renkli "mürekkep" bulunur, metin satırları
/// maskelenir (kısa şekil etiketleri bırakılır), kalan mürekkep birleştirilip
/// bölgelere ayrılır, sayfa dışı alanlar (masa, kitap kenarı, şerit) atılır ve
/// her bölge sınıflanır:
///   photo      — dokulu, renkli, basılı çizgi az (ör. güneş paneli fotoğrafı)
///   table      — en az 3 yatay ve 2 dikey uzun çizgi
///   chart      — sol ve alt eksen + eksende en az 3 sayısal etiket
///   annotation — basılı olmayan ince çizgiler (el yazısı, kalem işareti)
///   diagram    — geometri şekli, şema, deney düzeneği
///
/// Eşikler Python prototipinde örnek fotoğraflarla ayarlanmıştır; değişiklikler
/// iki tarafta birlikte yapılmalıdır.

class FigureRegion {
  const FigureRegion({required this.kind, required this.box, required this.labels});
  final String kind; // photo | table | chart | diagram | annotation

  /// Normalize kutu: sol, üst, sağ, alt (0–1).
  final List<double> box;

  /// İçindeki kısa etiket sayısı ("A", "x", "30°").
  final int labels;

  String get label => switch (kind) {
        'photo' => 'Fotoğraf',
        'table' => 'Tablo',
        'chart' => 'Grafik',
        'annotation' => 'İşaret',
        _ => 'Şekil',
      };

  Map<String, Object> toJson() => {
        'kind': kind,
        'box': [for (final v in box) (v * 1000).round() / 1000],
        'labels': labels,
      };
}

/// Görüntü üzerindeki bir metin satırının kutusu (görüntü pikseliyle).
class TextBox {
  const TextBox(this.text, this.left, this.top, this.width, this.height);
  final String text;
  final double left, top, width, height;

  /// Kısa ifade: şekil etiketi sayılır, maskelenmez.
  bool get isLabel => text.replaceAll(' ', '').length <= 4;
  bool get hasDigit => text.contains(RegExp(r'\d'));
}

/// İş parçacığına gönderilecek iş.
class FigureJob {
  const FigureJob(this.rgba, this.width, this.height, this.boxes);
  final Uint8List rgba; // RGBA, satır satır
  final int width;
  final int height;
  final List<TextBox> boxes;
}

/// `compute` için üst düzey giriş noktası.
List<FigureRegion> detectFiguresTask(FigureJob job) =>
    detectFigures(job.rgba, job.width, job.height, job.boxes);

/// (2r+1)² penceresinde ortalama (integral görüntüyle; kenarda kırpılır).
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
    final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
      final s = integ[y1 * (w + 1) + x1] - integ[y0 * (w + 1) + x1] - integ[y1 * (w + 1) + x0] + integ[y0 * (w + 1) + x0];
      out[y * w + x] = s / ((y1 - y0) * (x1 - x0));
    }
  }
  return out;
}

int _longestRun(bool Function(int i) at, int n) {
  var best = 0, cur = 0;
  for (var i = 0; i < n; i++) {
    cur = at(i) ? cur + 1 : 0;
    if (cur > best) best = cur;
  }
  return best;
}

List<FigureRegion> detectFigures(Uint8List rgba, int w, int h, List<TextBox> boxes) {
  final n = w * h;
  final lum = Float64List(n);
  final sat = Float64List(n);
  for (var i = 0; i < n; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    lum[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    sat[i] = (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b))).toDouble();
  }
  final bg = _boxMean(lum, w, h, 15);
  final paper = List<bool>.generate(n, (i) => lum[i] > bg[i] - 12 && sat[i] < 60);
  final dark = List<bool>.generate(n, (i) => lum[i] < bg[i] - 25);
  final ink = List<bool>.generate(n, (i) => dark[i] || (sat[i] > 70 && lum[i] < bg[i] - 12));

  // Metin satırları maskelenir (şekil etiketleri hariç).
  for (final t in boxes) {
    if (t.isLabel) continue;
    final x0 = math.max(0, t.left.floor() - 3), y0 = math.max(0, t.top.floor() - 3);
    final x1 = math.min(w, (t.left + t.width).floor() + 3), y1 = math.min(h, (t.top + t.height).floor() + 3);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        ink[y * w + x] = false;
      }
    }
  }

  // Yakın mürekkebi birleştir (yarıçap 4) ve bağlı bileşenler (4 komşu).
  final inkF = Float64List(n);
  for (var i = 0; i < n; i++) {
    if (ink[i]) inkF[i] = 1;
  }
  final grownMean = _boxMean(inkF, w, h, 4);
  final labels = Int32List(n)..fillRange(0, n, -1);
  final queue = Int32List(n);
  final comps = <List<int>>[];
  for (var start = 0; start < n; start++) {
    if (grownMean[start] <= 0 || labels[start] >= 0) continue;
    final id = comps.length;
    var head = 0, tail = 0;
    queue[tail++] = start;
    labels[start] = id;
    var minX = start % w, maxX = minX, minY = start ~/ w, maxY = minY;
    while (head < tail) {
      final p = queue[head++];
      final px = p % w, py = p ~/ w;
      for (final (nx, ny) in [(px, py + 1), (px, py - 1), (px + 1, py), (px - 1, py)]) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final q = ny * w + nx;
        if (grownMean[q] > 0 && labels[q] < 0) {
          labels[q] = id;
          queue[tail++] = q;
          if (nx < minX) minX = nx;
          if (nx > maxX) maxX = nx;
          if (ny < minY) minY = ny;
          if (ny > maxY) maxY = ny;
        }
      }
    }
    comps.add([minX, minY, maxX + 1, maxY + 1]);
  }

  final out = <FigureRegion>[];
  for (final c in comps) {
    final x0 = c[0], y0 = c[1], x1 = c[2], y1 = c[3];
    final rw = x1 - x0, rh = y1 - y0;
    if (rw < 24 || rh < 24 || rw * rh < 0.006 * w * h) continue;
    final area = rw * rh;
    var inkCount = 0, paperCount = 0, colorCount = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = y * w + x;
        if (ink[i]) inkCount++;
        if (paper[i]) {
          paperCount++;
        } else if (sat[i] > 70) {
          colorCount++;
        }
      }
    }
    final inkFrac = inkCount / area;
    if (inkFrac < 0.01) continue;
    final touches = x0 <= 2 || y0 <= 2 || x1 >= w - 2 || y1 >= h - 2;
    final rx0 = math.max(0, x0 - 8), ry0 = math.max(0, y0 - 8), rx1 = math.min(w, x1 + 8), ry1 = math.min(h, y1 + 8);
    var ringPaper = 0;
    for (var y = ry0; y < ry1; y++) {
      for (var x = rx0; x < rx1; x++) {
        if (x >= x0 && x < x1 && y >= y0 && y < y1) continue;
        if (paper[y * w + x]) ringPaper++;
      }
    }
    final ringFrac = ringPaper / math.max(1, (ry1 - ry0) * (rx1 - rx0) - area);
    final paperIn = paperCount / area;
    final edges = (x0 <= 2 ? 1 : 0) + (y0 <= 2 ? 1 : 0) + (x1 >= w - 2 ? 1 : 0) + (y1 >= h - 2 ? 1 : 0);
    if (edges >= 2 || (touches && (rw > 0.85 * w || rh > 0.85 * h))) continue; // şerit, kenar, masa
    if (touches && ringFrac < 0.5) continue;
    if (ringFrac < 0.35) continue;

    // Doku: kâğıt dışı piksellerde güçlü geçiş oranı; basılı mürekkep: koyu ve renksiz.
    var npCount = 0, strong = 0;
    for (var y = y0; y < y1 - 1; y++) {
      for (var x = x0; x < x1 - 1; x++) {
        final i = y * w + x;
        if (paper[i]) continue;
        npCount++;
        final g = (lum[i + 1] - lum[i]).abs() + (lum[i + w] - lum[i]).abs();
        if (g > 40) strong++;
      }
    }
    final texture = npCount == 0 ? 0.0 : strong / npCount;
    var printedCount = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = y * w + x;
        if (ink[i] && lum[i] < bg[i] - 60 && sat[i] < 50) printedCount++;
      }
    }
    final printed = inkCount == 0 ? 0.0 : printedCount / inkCount;
    final colorFrac = colorCount / area;

    bool darkAt(int x, int y) => dark[(y0 + y) * w + x0 + x];
    var hLines = 0, vLines = 0;
    for (var y = 0; y < rh; y++) {
      if (_longestRun((x) => darkAt(x, y), rw) >= 0.6 * rw) hLines++;
    }
    for (var x = 0; x < rw; x++) {
      if (_longestRun((y) => darkAt(x, y), rh) >= 0.6 * rh) vLines++;
    }
    bool axes() {
      var left = false, bottom = false;
      for (var x = 0; x < math.min(rw, math.max(3, rw ~/ 5)) && !left; x++) {
        left = _longestRun((y) => darkAt(x, y), rh) >= 0.6 * rh;
      }
      for (var y = math.max(0, rh - math.max(3, rh ~/ 4)); y < rh && !bottom; y++) {
        bottom = _longestRun((x) => darkAt(x, y), rw) >= 0.6 * rw;
      }
      return left && bottom;
    }

    bool inside(TextBox t) => x0 <= t.left && t.left <= x1 && y0 <= t.top && t.top <= y1;
    final labelCount = boxes.where((t) => t.isLabel && inside(t)).length;
    final numericAxis = boxes
        .where((t) =>
            t.isLabel && t.hasDigit && inside(t) && (t.left <= x0 + 0.15 * rw || t.top >= y1 - 0.15 * rh))
        .length;

    final String kind;
    if (1 - paperIn > 0.3 && texture > 0.2 && printed < 0.2) {
      kind = 'photo';
    } else if (hLines >= 3 && vLines >= 2) {
      kind = 'table';
    } else if (vLines >= 1 && hLines >= 1 && numericAxis >= 3 && axes()) {
      kind = 'chart';
    } else if (printed < 0.15 && colorFrac < 0.08 && labelCount == 0) {
      kind = 'annotation';
    } else {
      kind = 'diagram';
    }
    out.add(FigureRegion(kind: kind, box: [x0 / w, y0 / h, x1 / w, y1 / h], labels: labelCount));
  }
  return out;
}
