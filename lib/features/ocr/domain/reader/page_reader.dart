import 'dart:math' as math;

import '../question_text.dart';

/// Sayfa okuyucu: ML Kit satırlarından soruları, kökü, öncülleri, maddeleri,
/// soru cümlesini ve şıkları çıkarır. Saf Dart: test edilebilir, telefonda
/// arka planda çalışır.
///
/// Adımlar: eğim düzeltme → kenar süslerini atma → sütunlar → okuma sırası →
/// soru blokları ("4.", "4/", "ÖRNEK 26") → her blokta şıklar (konuma göre:
/// yan yana ve kesirli şıklar dahil), öncüller (I/II/III, bozuk okunsa da),
/// maddeler, soru cümlesi, şekil etiketleri, el yazısı gürültüsü → asıl soru.
///
/// Kurallar Python prototipinde örnek fotoğraflarla doğrulanmıştır; değişiklikler
/// iki tarafta birlikte yapılmalıdır.

class QuestionPart {
  const QuestionPart({
    required this.number,
    required this.label,
    required this.box,
    required this.partial,
    required this.stem,
    required this.bullets,
    required this.statements,
    required this.prompt,
    required this.options,
    required this.labels,
    required this.noise,
  });

  final int? number;
  final String? label; // "4." ya da "ÖRNEK 26"
  final List<double> box; // sol, üst, sağ, alt (piksel)
  final bool partial; // fotoğraf kenarından kesik
  final List<String> stem; // paragraflar
  final List<String> bullets; // madde imli bilgiler
  final List<({String label, String text})> statements; // öncüller
  final String prompt; // soru cümlesi
  final Map<String, String> options; // A → metin
  final List<String> labels; // şekil etiketleri ("A", "x", "30°")
  final int noise; // el yazısı / bozuk satır sayısı

  /// Kök + maddeler + öncüller + soru cümlesi: tek metin (arama ve rapor için).
  String get fullStem => [
        ...stem,
        ...bullets.map((b) => '• $b'),
        for (final s in statements) '${s.label}. ${s.text}',
        if (prompt.isNotEmpty) prompt,
      ].join('\n');

  Map<String, Object?> toJson() => {
        'number': number,
        'label': label,
        'box': [for (final v in box) v.round()],
        'partial': partial,
        'stem': stem,
        'bullets': bullets,
        'statements': [for (final s in statements) {'label': s.label, 'text': s.text}],
        'prompt': prompt,
        'options': options,
        'labels': labels,
        'noise': noise,
      };
}

class PageReading {
  const PageReading({required this.questions, required this.primary, required this.columns, required this.skew});
  final List<QuestionPart> questions;
  final int? primary; // asıl soru (sıra), yoksa null
  final int columns;
  final double skew; // düzeltilen eğim (derece)

  QuestionPart? get main => primary == null ? null : questions[primary!];

  Map<String, Object?> toJson() => {
        'questions': [for (final q in questions) q.toJson()],
        'primary': primary,
        'columns': columns,
        'skew': skew,
      };
}

final _mark = RegExp(r'^\(?([A-E]|©)\)(.*)$');
final _qStart = RegExp(r'^(\d{1,2})\s*[.\/)]\s*(.*)$');
final _ornek = RegExp(r'^(?:ÖRNEK|Örnek|ORNEK)\s*(\d{1,3})\b(.*)$');
final _roman = RegExp(
    r'^(IV|lV|III|Ill|lll|111|Ili|IIl|IlI|II|Il|ll|11|IL|lI|I|l|1|\||V)(?:\s*[.)]\s*|\s+(?=[A-ZÇĞİÖŞÜ]))(.*)$');
final _bullet = RegExp(r'^[\s*\u2022\u00bb\u00b7,]+(.*)$');
final _promptStart =
    RegExp(r'^(Buna göre|Verilen|Yukarıdaki|Aşağıdaki|Bu bilgilere|Bu durumda)', caseSensitive: false);
final _lowerWord = RegExp(r'[a-zçğıöşü]{3,}');
const _bulletChars = '*•»·,';

/// Okunan matematik ifadelerindeki tipik hataları düzeltir: "3V5" → "3√5",
/// "42*)" → "42°)", "sin?" → "sin²".
String mathNormalize(String t) => t
    .replaceAll(RegExp(r'(?<=\d)V(?=\d)'), '√')
    .replaceAll(RegExp(r'(?<![A-Za-zÇĞİÖŞÜçğıöşü])V(?=\d)'), '√')
    .replaceAllMapped(RegExp(r'(\d)\*(?=[\s),.;]|$)'), (m) => '${m[1]}°')
    .replaceAllMapped(RegExp(r'\b(sin|cos|tan|cot)\s*[?”"’]'), (m) => '${m[1]}²');

/// Bozuk okunmuş Roma rakamını etiketine çevirir ("Il" → "II", "Ili" → "III").
String romanLabel(String raw) {
  final r = raw.replaceAll('|', 'I');
  if (r == 'IV' || r == 'lV') return 'IV';
  if (r == 'V') return 'V';
  if (r.length >= 3) return 'III';
  if (r.length == 2) return 'II';
  return 'I';
}

double _median(List<double> xs, double fallback) {
  if (xs.isEmpty) return fallback;
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Kararlı sıralama (Python'daki gibi): eşitlikte ilk sıra korunur.
List<T> _stable<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = [for (final (i, x) in items.indexed) (i, x)];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final (_, x) in indexed) x];
}

bool _isLower(String c) => c.toLowerCase() == c && c.toUpperCase() != c;

/// Satırları paragraflara birleştirir; satır sonu tireli kelimeyi bitiştirir.
List<String> joinLines(List<OcrLine> lines, double lineHeight) {
  final paras = <String>[];
  var cur = '';
  OcrLine? prev;
  for (final l in lines) {
    final t = l.text.trim();
    if (t.isEmpty) continue;
    if (prev != null && l.top - (prev.top + prev.height) > 0.9 * lineHeight) {
      paras.add(cur);
      cur = '';
    }
    if (cur.endsWith('-') && _isLower(t.substring(0, 1))) {
      cur = cur.substring(0, cur.length - 1) + t;
    } else {
      cur = '$cur $t'.trim();
    }
    prev = l;
  }
  if (cur.isNotEmpty) paras.add(cur);
  return paras;
}

/// Satır açılarının (metin uzunluğuyla ağırlıklı) ortancası kadar geri döndürür.
({List<OcrLine> lines, double skew}) deskew(List<OcrLine> lines, double width, double height) {
  final angs = [
    for (final l in lines)
      if (l.angle.abs() < 15) (l.angle, l.text.length),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (angs.isEmpty) return (lines: lines, skew: 0);
  final total = angs.fold<int>(0, (s, a) => s + a.$2);
  var acc = 0;
  var med = 0.0;
  for (final (a, w) in angs) {
    acc += w;
    if (acc >= total / 2) {
      med = a;
      break;
    }
  }
  if (med.abs() < 0.5) return (lines: lines, skew: 0);
  final t = -med * math.pi / 180;
  final cx = width / 2, cy = height / 2;
  (double, double) tr(double x, double y) {
    final dx = x - cx, dy = y - cy;
    return (cx + dx * math.cos(t) - dy * math.sin(t), cy + dx * math.sin(t) + dy * math.cos(t));
  }

  return (
    lines: [
      for (final l in lines)
        () {
          final (x, y) = tr(l.left, l.top);
          return l.moved(x, y, [
            for (final w in l.words)
              () {
                final (wx, wy) = tr(w.left, w.top);
                return w.moved(wx, wy);
              }(),
          ]);
        }(),
    ],
    skew: med,
  );
}

/// Dikey kenar yazısı (yayınevi adı, bölüm şeridi).
bool _decoration(OcrLine l) => l.height > 2.5 * l.width && l.text.replaceAll(' ', '').length >= 3;

/// İki sütunlu sayfada sütunlar; aradaki boşluk (oluk) yoksa tek sütun.
List<List<OcrLine>> splitColumns(List<OcrLine> lines, double width) {
  final bins = List<int>.filled(50, 0);
  for (final l in lines) {
    if (l.width > 0.6 * width) continue;
    final a = math.max(0, (l.left / width * 50).floor());
    final b = math.min(50, ((l.left + l.width) / width * 50).floor() + 1);
    for (var i = a; i < b; i++) {
      bins[i]++;
    }
  }
  (int, int)? best;
  var i = 8;
  while (i < 47) {
    if (bins[i] == 0) {
      var j = i;
      while (j < 47 && bins[j] == 0) {
        j++;
      }
      if (j - i >= 2 && (best == null || j - i > best.$2 - best.$1)) best = (i, j);
      i = j;
    } else {
      i++;
    }
  }
  if (best == null) return [lines];
  final cut = (best.$1 + best.$2) / 2 / 50 * width;
  final left = [for (final l in lines) if (l.left + l.width / 2 < cut) l];
  final right = [for (final l in lines) if (l.left + l.width / 2 >= cut) l];
  if (left.length < 3 || right.length < 3) return [lines];
  return [left, right];
}

/// Okuma sırası: satırlar yüksekliğin yarısı kadar toleransla sıralara, sıralar soldan sağa.
List<OcrLine> readingOrderOf(List<OcrLine> lines) {
  if (lines.isEmpty) return const [];
  final tol = _median([for (final l in lines) l.height], 16) * 0.5;
  final rows = <List<OcrLine>>[];
  for (final l in _stable(lines, (a, b) => a.top.compareTo(b.top))) {
    if (rows.isNotEmpty && (l.top - rows.last.first.top).abs() <= tol) {
      rows.last.add(l);
    } else {
      rows.add([l]);
    }
  }
  return [for (final r in rows) ..._stable(r, (a, b) => a.left.compareTo(b.left))];
}

class _Block {
  _Block(this.number, this.label);
  final int? number;
  final String? label;
  final lines = <OcrLine>[];
}

List<_Block> _segment(List<OcrLine> column, double width) {
  final ordered = readingOrderOf(column);
  if (ordered.isEmpty) return const [];
  final xs = [for (final l in ordered) l.left]..sort();
  final left = xs[xs.length ~/ 10];
  final blocks = <_Block>[];
  var cur = _Block(null, null);
  for (final l in ordered) {
    final t = l.text.trim();
    final m = _qStart.firstMatch(t);
    final o = _ornek.firstMatch(t);
    (int, String)? start;
    if (o != null) {
      start = (int.parse(o[1]!), 'ÖRNEK ${o[1]}');
    } else if (m != null && l.left <= left + 0.04 * width && l.confidence >= 0.45) {
      final n = int.parse(m[1]!);
      if (n >= 1 && n <= 99) start = (n, '$n.');
    }
    if (start != null) {
      if (cur.lines.isNotEmpty) blocks.add(cur);
      cur = _Block(start.$1, start.$2);
    }
    cur.lines.add(l);
  }
  if (cur.lines.isNotEmpty) blocks.add(cur);
  return blocks;
}

class _Mark {
  _Mark(this.word, this.letter, this.rest);
  final OcrWord word;
  final String letter;
  final String rest;
  late double x0, y0, x1, y1;
  double get top => word.top;
  double get left => word.left;
}

List<T> _groupRows<T>(List<T> items, double tol, double Function(T) top, double Function(T) left) {
  final rows = <List<T>>[];
  for (final it in _stable(items, (a, b) => top(a).compareTo(top(b)))) {
    if (rows.isNotEmpty) {
      final mean = rows.last.fold<double>(0, (s, x) => s + top(x)) / rows.last.length;
      if ((top(it) - mean).abs() <= tol) {
        rows.last.add(it);
        continue;
      }
    }
    rows.add([it]);
  }
  return [for (final r in rows) ..._stable(r, (a, b) => left(a).compareTo(left(b)))];
}

QuestionPart _parseBlock(_Block b, double width, double height) {
  final lines = b.lines;
  final words = [
    for (final l in lines)
      for (final w in l.words)
        if (w.confidence >= 0.45 || _mark.hasMatch(w.text)) w,
  ];
  final mh = _median([for (final l in lines) l.height], 16);
  final wh = _median([for (final w in words) w.height], mh);

  // Şıklar: işaret kelimeleri; önce sıralar, sonra soldan sağa; A'dan artan dizi.
  final marks = <_Mark>[];
  for (final w in words) {
    final m = _mark.firstMatch(w.text);
    if (m != null) marks.add(_Mark(w, m[1] == '©' ? 'C' : m[1]!, m[2]!));
  }
  final ordered = _groupRows<_Mark>(marks, 0.9 * wh, (m) => m.top, (m) => m.left);
  const want = 'ABCDE';
  final seq = <_Mark>[];
  for (final m in ordered) {
    if (seq.length < 5 && m.letter == want[seq.length]) seq.add(m);
  }

  final options = <String, String>{};
  var body = lines;
  if (seq.length >= 3) {
    final rows = <List<_Mark>>[];
    for (final m in seq) {
      if (rows.isNotEmpty) {
        final mean = rows.last.fold<double>(0, (s, x) => s + x.top) / rows.last.length;
        if ((m.top - mean).abs() <= 0.9 * wh) {
          rows.last.add(m);
          continue;
        }
      }
      rows.add([m]);
    }
    final first = rows.first.first;
    var top0 = first.top - 1.6 * wh;
    for (final l in lines) {
      // İşaretin sol hizasından başlayan üst satır kesrin payı değil, metindir.
      final cy = l.top + l.height / 2;
      if (top0 < cy && cy < first.top && l.left <= first.left + 0.5 * first.word.width) {
        top0 = math.max(top0, l.top + l.height);
      }
    }
    for (var ri = 0; ri < rows.length; ri++) {
      final row = rows[ri];
      for (var mi = 0; mi < row.length; mi++) {
        final m = row[mi];
        m.x0 = m.left;
        m.x1 = mi + 1 < row.length ? row[mi + 1].left : double.infinity;
        m.y0 = ri > 0 ? rows[ri - 1].map((x) => x.top + x.word.height).reduce(math.max) : top0;
        m.y1 = ri + 1 < rows.length
            ? rows[ri + 1].map((x) => x.top).reduce(math.min)
            : m.top + m.word.height + 1.6 * wh;
      }
    }
    final markWords = {for (final m in seq) m.word};
    final assigned = {for (final m in seq) m.letter: <OcrWord>[]};
    for (final w in words) {
      if (markWords.contains(w)) continue;
      final cx = w.left + w.width / 2, cy = w.top + w.height / 2;
      if (cy < top0) continue;
      for (final m in seq) {
        if (m.x0 <= cx && cx < m.x1 && m.y0 <= cy && cy < m.y1) {
          assigned[m.letter]!.add(w);
          break;
        }
      }
    }
    String join(List<OcrWord> ws) => _stable(ws, (a, b) {
          final ra = ((a.top + a.height / 2) / (0.8 * wh)).round();
          final rb = ((b.top + b.height / 2) / (0.8 * wh)).round();
          return ra != rb ? ra.compareTo(rb) : a.left.compareTo(b.left);
        }).map((w) => w.text).join(' ');
    for (final m in seq) {
      final ws = assigned[m.letter]!;
      final mc = m.top + m.word.height / 2;
      final above = [for (final w in ws) if (w.top + w.height / 2 < mc - 0.5 * wh) w];
      final below = [for (final w in ws) if (w.top + w.height / 2 > mc + 0.5 * wh) w];
      final inline = [for (final w in ws) if (!above.contains(w) && !below.contains(w)) w];
      var text = [m.rest, join(inline)].where((p) => p.isNotEmpty).join(' ').trim();
      if (above.isNotEmpty && below.isNotEmpty && text.isEmpty) {
        text = '${join(above)} / ${join(below)}';
      } else if (above.isNotEmpty || below.isNotEmpty) {
        text = [join(above), text, join(below)].where((p) => p.isNotEmpty).join(' ');
      }
      options[m.letter] = mathNormalize(text.trim());
    }
    body = [for (final l in lines) if (l.top + l.height / 2 < top0) l];
  }

  // Gövde: gürültü, şekil etiketleri, öncüller, maddeler, soru cümlesi, kök.
  final stem = <OcrLine>[];
  final bullets = <String>[];
  final statements = <({String label, String text})>[];
  final prompt = <OcrLine>[];
  final labels = <String>[];
  var noise = 0;
  (String, double)? last;
  final bodyLeft = body.isEmpty ? 0.0 : body.map((l) => l.left).reduce(math.min);
  for (final (i, l) in body.indexed) {
    var t = l.text.trim();
    if (i == 0 && b.label != null) {
      final m = _qStart.firstMatch(t) ?? _ornek.firstMatch(t);
      if (m != null) t = m[2]!.trim();
    }
    if (t.isEmpty) continue; // yalnızca numaradan oluşan satır ("2.")
    if (l.confidence < 0.45) {
      noise++;
      continue;
    }
    if (t.replaceAll(' ', '').length <= 5 && !_lowerWord.hasMatch(t) && !t.contains('?')) {
      labels.add(t); // şekil etiketi: "E", "α", "17 m", "30°"
      continue;
    }
    if (t.length < 2) {
      noise++;
      continue;
    }
    final rm = _roman.firstMatch(t);
    final bm = _bullet.firstMatch(t);
    if (rm != null && rm[2]!.isNotEmpty && l.left > bodyLeft + 0.02 * width) {
      statements.add((label: romanLabel(rm[1]!), text: rm[2]!));
      last = ('s', l.left);
      continue;
    }
    if (bm != null && bm[1]!.isNotEmpty && _bulletChars.contains(t[0])) {
      bullets.add(bm[1]!);
      last = ('b', l.left);
      continue;
    }
    if (last != null && l.left > last.$2 + 0.02 * width) {
      if (last.$1 == 's') {
        final s = statements.removeLast();
        statements.add((label: s.label, text: '${s.text} $t'));
        continue;
      }
      if (last.$1 == 'b') {
        bullets[bullets.length - 1] = '${bullets.last} $t';
        continue;
      }
    }
    last = null;
    final line = OcrLine(t, left: l.left, top: l.top, height: l.height, width: l.width, confidence: l.confidence);
    if (_promptStart.hasMatch(t) || t.contains('?') || prompt.isNotEmpty) {
      prompt.add(line);
      continue;
    }
    stem.add(line);
  }
  const order = ['I', 'II', 'III', 'IV', 'V'];
  final labelsNow = [for (final s in statements) s.label];
  final ordered2 = order.take(statements.length).toList();
  final relabel = labelsNow.length != ordered2.length ||
      [for (var k = 0; k < labelsNow.length; k++) labelsNow[k] == ordered2[k]].contains(false);
  final fixedStatements = relabel
      ? [for (final (k, s) in statements.indexed) (label: k < 5 ? order[k] : '${k + 1}', text: s.text)]
      : statements;

  final box = [
    lines.map((l) => l.left).reduce(math.min),
    lines.map((l) => l.top).reduce(math.min),
    lines.map((l) => l.left + l.width).reduce(math.max),
    lines.map((l) => l.top + l.height).reduce(math.max),
  ];
  final partial =
      box[0] <= 0.015 * width || box[1] <= 0.015 * height || box[2] >= 0.985 * width || box[3] >= 0.985 * height;
  return QuestionPart(
    number: b.number,
    label: b.label,
    box: box,
    partial: partial,
    stem: [for (final p in joinLines(stem, mh)) mathNormalize(p)],
    bullets: [for (final x in bullets) mathNormalize(x)],
    statements: [for (final s in fixedStatements) (label: s.label, text: mathNormalize(s.text))],
    prompt: mathNormalize(joinLines(prompt, mh).join(' ')),
    options: options,
    labels: labels,
    noise: noise,
  );
}

/// Kelime kutusu gelmeyen satırlar (eski kayıtlar, testler): metin kelimelere
/// bölünür, genişlik harf sayısıyla orantılı dağıtılır.
List<OcrLine> withWords(List<OcrLine> lines) => [
      for (final l in lines)
        if (l.words.isNotEmpty)
          l
        else
          () {
            final width = l.width > 0 ? l.width : l.text.length * l.height * 0.5;
            final total = math.max(1, l.text.length);
            var cx = l.left;
            final words = <OcrWord>[];
            for (final p in l.text.split(' ').where((p) => p.isNotEmpty)) {
              final pw = width * p.length / total;
              words.add(OcrWord(p, left: cx, top: l.top, width: pw, height: l.height, confidence: l.confidence));
              cx += pw + width / total;
            }
            return OcrLine(l.text,
                left: l.left,
                top: l.top,
                height: l.height,
                width: width,
                confidence: l.confidence,
                angle: l.angle,
                words: words);
          }(),
    ];

/// Sayfayı okur. [preferredNumber] verilirse (kartın soru numarası) o soru asıl seçilir.
PageReading readPage(List<OcrLine> rawLines, double width, double height, {int? preferredNumber}) {
  final d = deskew(rawLines, width, height);
  final lines = [for (final l in d.lines) if (!_decoration(l)) l];
  final cols = splitColumns(lines, width);
  final out = <QuestionPart>[
    for (final col in cols)
      for (final b in _segment(col, width)) _parseBlock(b, width, height),
  ];
  double score(QuestionPart q) {
    var s = 0.0;
    if (q.options.length >= 4) s += 3;
    if (q.prompt.isNotEmpty) s += 1;
    if (q.partial) s -= 3;
    final cx = (q.box[0] + q.box[2]) / 2 / width, cy = (q.box[1] + q.box[3]) / 2 / height;
    final dist = math.sqrt(math.pow(cx - 0.5, 2) + math.pow(cy - 0.5, 2));
    s += 2 * (1 - math.min(1, dist / 0.71)) + 2 * (q.box[2] - q.box[0]) * (q.box[3] - q.box[1]) / (width * height);
    if (preferredNumber != null && q.number == preferredNumber) s += 6;
    return s;
  }

  int? primary;
  var best = double.negativeInfinity;
  for (final (i, q) in out.indexed) {
    final s = score(q);
    if (s > best) {
      best = s;
      primary = i;
    }
  }
  return PageReading(questions: out, primary: primary, columns: cols.length, skew: d.skew);
}

/// Sayfanın yönü (0, 90, 180, 270): satır açılarının metin uzunluğuyla
/// ağırlıklı çoğunluğu. Belirsizse (%60 altı) 0.
int dominantRotation(List<OcrLine> lines) {
  final weight = <int, int>{0: 0, 90: 0, 180: 0, 270: 0};
  var total = 0;
  for (final l in lines) {
    final a = ((l.angle % 360) + 360) % 360;
    final bucket = ((a / 90).round() % 4) * 90;
    weight[bucket] = weight[bucket]! + l.text.length;
    total += l.text.length;
  }
  if (total == 0) return 0;
  final best = weight.entries.reduce((a, b) => b.value > a.value ? b : a);
  return best.value >= 0.6 * total ? best.key : 0;
}
