/// Okul karnesi PDF'ini (ör. "VİP - MAARİF 11.SINIF - 1") veriye çevirir.
///
/// Girdi, PDF'ten çıkarılmış kelimeler ve konumlarıdır; ayrıştırıcı platformdan
/// bağımsızdır (test edilebilir). Karne iki bölümden oluşur:
///  - Sayfa 1 "BÖLÜM ANALİZİ": ders ders soru, doğru, yanlış, boş, net;
///    sağda puan ve sıralar.
///  - Sonraki sayfalar: üç sütunlu soru tabloları. Her satır: NO, KAZANIM,
///    DC (doğru cevap), ÖC (öğrenci cevabı), SN (+ doğru, - yanlış, # boş).
///
/// Sütunlar "DC" başlıklarının yatay konumundan bulunur. Cevap harfleri kazanım
/// satırından ~1,5 nokta yukarıda basıldığından, her cevap üçlüsü aynı
/// sütundaki en yakın kazanım satırına eşlenir. Bir sütun önceki sütundaki
/// tablonun devamıyla başlayabilir; ders bilgisi sütunlar arasında taşınır.
library;

class PdfWord {
  const PdfWord(this.text, this.x, this.y);

  final String text;
  final double x; // sol kenar (nokta)
  final double y; // üst kenar (nokta)
}

class KarneSection {
  const KarneSection({
    required this.rawName,
    required this.questionCount,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.net,
  });

  final String rawName; // "DİN KÜLTÜRÜ"
  final int questionCount;
  final int correct;
  final int wrong;
  final int blank;
  final double net;
}

enum KarneResult { correct, wrong, blank }

class KarneQuestion {
  const KarneQuestion({
    required this.subjectRaw,
    required this.no,
    required this.kazanim,
    required this.result,
    this.correctAnswer,
    this.givenAnswer,
  });

  final String subjectRaw;
  final int no; // kitapçıktaki numara
  final String kazanim;
  final KarneResult result;
  final String? correctAnswer; // DC
  final String? givenAnswer; // ÖC
}

class KarneData {
  const KarneData({
    required this.title,
    required this.student,
    required this.sections,
    required this.questions,
    this.booklet,
    this.date,
    this.examType,
    this.score,
    this.ranks = const [],
    this.osymRank,
  });

  final String title;
  final String student;
  final String? booklet; // "A", "B"
  final DateTime? date;
  final String? examType; // TYT | AYT | YDT
  final String? score; // "445.180"
  /// Sınıf, okul, genel: (sıra, katılım).
  final List<(int, int)> ranks;
  final int? osymRank;
  final List<KarneSection> sections;
  final List<KarneQuestion> questions;
}

class KarneFormatException implements Exception {
  const KarneFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ───────────────────────── Yardımcılar ─────────────────────────

class _Row {
  _Row(this.y, this.words);
  final double y;
  final List<PdfWord> words;

  String get text => words.map((w) => w.text).join(' ');
  List<String> get tokens => text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
}

/// Kelimeleri yüksekliğe göre satırlara toplar (satır içinde soldan sağa).
List<_Row> _rows(Iterable<PdfWord> words, {double tolerance = 2.5}) {
  final sorted = words.toList()
    ..sort((a, b) {
      final c = a.y.compareTo(b.y);
      return c != 0 ? c : a.x.compareTo(b.x);
    });
  final out = <_Row>[];
  for (final w in sorted) {
    if (out.isNotEmpty && (out.last.y - w.y).abs() <= tolerance) {
      out.last.words.add(w);
    } else {
      out.add(_Row(w.y, [w]));
    }
  }
  for (final r in out) {
    r.words.sort((a, b) => a.x.compareTo(b.x));
  }
  return out;
}

final _number = RegExp(r'^-?\d+(\.\d+)?$');
final _integer = RegExp(r'^\d+$');
final _digit = RegExp(r'\d');
final _bookletDate = RegExp(r'([A-ZÇĞİÖŞÜ])\s*K[İI]TAP[ÇC]I[ĞG]I\s*/\s*(\d{2})\.(\d{2})\.(\d{4})');

// ───────────────────────── Ayrıştırma ─────────────────────────

KarneData parseKarne(List<List<PdfWord>> pages) {
  if (pages.isEmpty || pages.first.isEmpty) {
    throw const KarneFormatException('PDF\'te okunabilir metin bulunamadı (taranmış görüntü olabilir).');
  }
  final first = pages.first;
  final firstText = first.map((w) => w.text).join(' ');
  if (firstText.contains('DERS ANALİZİ') && !firstText.contains('BÖLÜM ANALİZİ')) {
    throw const KarneFormatException(
      'Bu bir birleştirilmiş karne. Denemeleri tek tek eklemek için her denemenin kendi karnesini seç.',
    );
  }

  // ── Başlık: ad, öğrenci, kitapçık ve tarih ──
  final head = _rows(first.where((w) => w.y < 120));
  if (head.isEmpty) throw const KarneFormatException('Karnenin başlığı okunamadı.');
  final title = head.first.text.trim();
  final student = head.length > 1 ? head[1].text.trim() : '';
  String? booklet;
  DateTime? date;
  for (final r in head) {
    final m = _bookletDate.firstMatch(r.text);
    if (m != null) {
      booklet = m.group(1);
      date = DateTime(int.parse(m.group(4)!), int.parse(m.group(3)!), int.parse(m.group(2)!));
      break;
    }
  }

  // ── Bölüm analizi tablosu (solda) ──
  final left = first.where((w) => w.x < 410).toList();
  final toplam = left.where((w) => w.text == 'TOPLAM').map((w) => w.y).toList();
  final limit = toplam.isEmpty ? 380.0 : toplam.first + 3;
  final sections = <KarneSection>[];
  for (final r in _rows(left.where((w) => w.y < limit))) {
    final t = r.tokens;
    if (t.length < 7 || !_integer.hasMatch(t.first)) continue;
    var i = 1;
    final name = <String>[];
    while (i < t.length && !_number.hasMatch(t[i])) {
      name.add(t[i]);
      i++;
    }
    final nums = t.sublist(i);
    if (name.isEmpty || nums.length < 5) continue;
    final count = int.tryParse(nums[0]);
    final c = int.tryParse(nums[1]);
    final w = int.tryParse(nums[2]);
    final b = int.tryParse(nums[3]);
    final net = double.tryParse(nums[4]);
    if (count == null || c == null || w == null || b == null || net == null) continue;
    sections.add(KarneSection(
      rawName: name.join(' '),
      questionCount: count,
      correct: c,
      wrong: w,
      blank: b,
      net: net,
    ));
  }
  if (sections.isEmpty) {
    throw const KarneFormatException('Karnede "Bölüm Analizi" tablosu bulunamadı; bu karne biçimi tanınmadı.');
  }

  // ── Puan ve sıralar (sağda): puan, sınıf, okul, genel, ÖSYM ──
  String? examType;
  final numbers = <String>[];
  for (final r in _rows(first.where((w) => w.x >= 410 && w.y < limit + 30))) {
    for (final tok in r.tokens) {
      if (examType == null && (tok == 'TYT' || tok == 'AYT' || tok == 'YDT')) {
        examType = tok;
      } else if (_number.hasMatch(tok)) {
        numbers.add(tok);
      }
    }
  }
  String? score;
  final ranks = <(int, int)>[];
  int? osym;
  if (numbers.isNotEmpty) {
    score = numbers.first.contains('.') ? numbers.first : null;
    final ints = [for (final n in numbers.skip(score == null ? 0 : 1)) int.tryParse(n)].whereType<int>().toList();
    for (var i = 0; i + 1 < ints.length && ranks.length < 3; i += 2) {
      ranks.add((ints[i], ints[i + 1]));
    }
    if (ints.length.isOdd) osym = ints.last;
  }

  return KarneData(
    title: title,
    student: student,
    booklet: booklet,
    date: date,
    examType: examType,
    score: score,
    ranks: ranks,
    osymRank: osym,
    sections: sections,
    questions: _parseQuestions(pages.skip(1)),
  );
}

List<KarneQuestion> _parseQuestions(Iterable<List<PdfWord>> pages) {
  final out = <KarneQuestion>[];
  String? subject;
  for (final words in pages) {
    final dcs = words.where((w) => w.text == 'DC').toList()..sort((a, b) => a.x.compareTo(b.x));
    final columns = <double>[];
    for (final d in dcs) {
      if (columns.isEmpty || (columns.last - d.x).abs() > 15) columns.add(d.x);
    }
    for (var ci = 0; ci < columns.length; ci++) {
      final dcX = columns[ci];
      final leftEdge = ci == 0 ? 0.0 : columns[ci - 1] + 32;
      final answerFrom = dcX - 3;
      final answerTo = dcX + 32;
      final col = words.where((w) => w.x >= leftEdge - 1 && w.x < answerTo && w.y > 118).toList();
      final headerYs = col.where((w) => w.text == 'DC').map((w) => w.y).toList()..sort();
      final allRows = _rows(col);

      // Olaylar: ders başlıkları ve soru satırları, yukarıdan aşağı.
      final events = <(double, String?, _Row?)>[];
      for (final h in headerYs) {
        final above = allRows
            .where((r) => r.y >= h - 17 && r.y <= h - 4 && !_digit.hasMatch(r.text) && !r.text.contains('KAZANIM'))
            .toList();
        if (above.isNotEmpty) events.add((above.last.y, above.last.text.trim(), null));
      }
      for (final r in _rows(col.where((w) => w.x < answerFrom))) {
        final t = r.tokens;
        if (t.length > 1 && _integer.hasMatch(t.first)) events.add((r.y, null, r));
      }
      final answers = <(double, List<String>)>[];
      for (final r in _rows(col.where((w) => w.x >= answerFrom))) {
        final t = r.tokens;
        if (t.isEmpty || t.contains('DC')) continue;
        if (t.last == '+' || t.last == '-' || t.last == '#') answers.add((r.y, t));
      }
      events.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        if (c != 0) return c;
        return (a.$2 != null ? 0 : 1).compareTo(b.$2 != null ? 0 : 1); // başlık önce
      });

      for (final (y, title, row) in events) {
        if (title != null) {
          subject = title;
          continue;
        }
        final current = subject;
        if (row == null || current == null) continue;
        final t = row.tokens;
        (double, List<String>)? best;
        for (final a in answers) {
          if (best == null || (a.$1 - y).abs() < (best.$1 - y).abs()) best = a;
        }
        if (best == null || (best.$1 - y).abs() > 6) continue;
        final mark = best.$2.last;
        final letters = best.$2.sublist(0, best.$2.length - 1);
        out.add(KarneQuestion(
          subjectRaw: current,
          no: int.parse(t.first),
          kazanim: t.sublist(1).join(' '),
          result: switch (mark) {
            '+' => KarneResult.correct,
            '-' => KarneResult.wrong,
            _ => KarneResult.blank,
          },
          correctAnswer: letters.isNotEmpty ? letters.first : null,
          givenAnswer: letters.length > 1 ? letters[1] : null,
        ));
      }
    }
  }
  return out;
}
