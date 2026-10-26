/// Fotoğraftan okunan bir satır ve ekrandaki konumu (piksel).
/// Okunan bir kelime ve sayfadaki kutusu (piksel).
class OcrWord {
  const OcrWord(this.text, {this.left = 0, this.top = 0, this.width = 0, this.height = 0, this.confidence = 1});
  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  /// 0–1 (ML Kit); el yazısı ve bozuk okumalar düşük çıkar.
  final double confidence;

  OcrWord moved(double left, double top) =>
      OcrWord(text, left: left, top: top, width: width, height: height, confidence: confidence);
}

class OcrLine {
  const OcrLine(
    this.text, {
    this.left = 0,
    this.top = 0,
    this.height = 0,
    this.width = 0,
    this.confidence = 1,
    this.angle = 0,
    this.words = const [],
  });
  final String text;
  final double left;
  final double top;
  final double height;
  final double width;

  /// 0–1 (ML Kit); el yazısı ve bozuk okumalar düşük çıkar.
  final double confidence;

  /// Satırın eğimi (derece, ML Kit); sayfa yönü ve eğim düzeltmesi için.
  final double angle;
  final List<OcrWord> words;

  OcrLine moved(double left, double top, List<OcrWord> words) => OcrLine(text,
      left: left, top: top, height: height, width: width, confidence: confidence, angle: angle, words: words);

  Map<String, Object> toJson() => {
        't': text,
        'x': left.round(),
        'y': top.round(),
        'h': height.round(),
        'w': width.round(),
        'c': (confidence * 100).round() / 100,
      };
}

/// Okunan metnin ayrıştırılmış hâli: soru numarası, kök ve şıklar.
class ParsedQuestion {
  const ParsedQuestion({required this.stem, this.number, this.options = const {}});
  final int? number;
  final String stem;
  final Map<String, String> options; // "A" → şık metni

  bool get hasOptions => options.isNotEmpty;
}

const _letters = ['A', 'B', 'C', 'D', 'E'];

/// Satır başında şık işareti: "A)", "A.", "(A)", "a)", "A -".
final _optionStart = RegExp(r'^\(?([A-Ea-e])\s*[\)\.\-:]\s*(.*)$');

/// Satır içinde (boşluktan sonra) şık işareti: "… B) 15".
final _optionInline = RegExp(r'\s\(?([A-E])\s*[\)\.]\s+');

/// Satır başında soru numarası: "12.", "12)", "12 -".
final _numberStart = RegExp(r'^(\d{1,3})\s*[\.\)\-]\s*(.*)$');

/// Satırları okuma sırasına koyar: yukarıdan aşağı; aynı hizadakiler soldan sağa.
List<OcrLine> readingOrder(List<OcrLine> lines) {
  if (lines.isEmpty) return const [];
  final heights = [for (final l in lines) if (l.height > 0) l.height]..sort();
  final tolerance = heights.isEmpty ? 8.0 : heights[heights.length ~/ 2] * 0.5;
  final sorted = [...lines]..sort((a, b) => a.top.compareTo(b.top));
  final rows = <List<OcrLine>>[];
  for (final l in sorted) {
    if (rows.isNotEmpty && (l.top - rows.last.first.top).abs() <= tolerance) {
      rows.last.add(l);
    } else {
      rows.add([l]);
    }
  }
  return [
    for (final row in rows) ...(row..sort((a, b) => a.left.compareTo(b.left))),
  ];
}

/// Bir satırı içindeki şık işaretlerinden böler: "A) 12 B) 15" → ["A) 12", "B) 15"].
List<String> _splitInline(String text) {
  final cuts = [for (final m in _optionInline.allMatches(text)) m.start + 1];
  if (cuts.isEmpty) return [text];
  final parts = <String>[];
  var from = 0;
  for (final c in cuts) {
    parts.add(text.substring(from, c).trim());
    from = c;
  }
  parts.add(text.substring(from).trim());
  return [for (final p in parts) if (p.isNotEmpty) p];
}

/// Okunan satırlardan soru numarası, kök ve şıkları çıkarır. Şık bölümü ancak
/// A'dan başlayıp sırayla en az iki şık bulunursa kabul edilir; yoksa tüm
/// metin köktür.
ParsedQuestion parseQuestion(List<OcrLine> lines) {
  final ordered = [for (final l in readingOrder(lines)) ..._splitInline(l.text.trim())];
  if (ordered.isEmpty) return const ParsedQuestion(stem: '');

  // Şık bölümünün başı: "A" işaretli ilk satır, ardından sırayla B (C, D, E).
  int? start;
  for (var i = 0; i < ordered.length && start == null; i++) {
    final m = _optionStart.firstMatch(ordered[i]);
    if (m == null || m.group(1)!.toUpperCase() != 'A') continue;
    final hasB = ordered.skip(i + 1).any((l) => _optionStart.firstMatch(l)?.group(1)?.toUpperCase() == 'B');
    if (hasB) start = i;
  }

  final options = <String, String>{};
  if (start != null) {
    String? current;
    var expected = 0; // sıradaki beklenen harf
    for (final line in ordered.skip(start)) {
      final m = _optionStart.firstMatch(line);
      final letter = m?.group(1)?.toUpperCase();
      if (m != null && expected < _letters.length && letter == _letters[expected]) {
        current = letter;
        options[current!] = m.group(2)!.trim();
        expected++;
      } else if (current != null) {
        options[current] = '${options[current]} ${line.trim()}'.trim(); // çok satırlı şık
      }
    }
  }

  final stemLines = [...ordered.take(start ?? ordered.length)];
  int? number;
  if (stemLines.isNotEmpty) {
    final m = _numberStart.firstMatch(stemLines.first);
    if (m != null) {
      number = int.parse(m.group(1)!);
      final rest = m.group(2)!.trim();
      if (rest.isEmpty) {
        stemLines.removeAt(0);
      } else {
        stemLines[0] = rest;
      }
    }
  }
  return ParsedQuestion(number: number, stem: stemLines.join('\n').trim(), options: options);
}
