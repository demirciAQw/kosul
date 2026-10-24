import 'dart:math' as math;

/// Bir çözüm kaydı: oturum bloğu, kitap testi ya da deneme bölümü.
class Observation {
  const Observation({
    required this.day,
    required this.subject,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.sessionKey,
    this.at,
    this.source,
    this.topic,
    this.secondsPerQuestion,
    this.sessionMinutes,
  });

  /// Saat biliniyorsa çözüm anı (denemelerde yok).
  final DateTime? at;

  /// Takvim günü (gün sayımı için).
  final DateTime day;
  final String subject;
  final String? source; // kitap adı, "Deneme" …
  final String? topic;
  final int correct;
  final int wrong;
  final int blank;
  final double? secondsPerQuestion;
  final int? sessionMinutes;

  /// Aynı oturumdan gelen kayıtları ayırt etmek için.
  final String sessionKey;

  int get total => correct + wrong + blank;
}

/// İncelenen etkenler. Her biri, karşılaştırmanın hangi koşullar sabit
/// tutularak yapılacağını ([contextOf]) ve düzeyini ([levelOf]) bilir.
enum Factor {
  timeOfDay('Günün saati'),
  dayType('Hafta içi / sonu'),
  pace('Çözüm hızı'),
  sessionLength('Oturum uzunluğu'),
  source('Kaynak'),
  topic('Konu'),
  period('Zaman içinde değişim');

  const Factor(this.title);
  final String title;
}

/// Bulgu: aynı koşullar altında iki düzey arasında güvenilir fark.
class Finding {
  const Finding({
    required this.factor,
    required this.better,
    required this.worse,
    required this.betterRate,
    required this.worseRate,
    required this.questions,
    required this.days,
    required this.strata,
    required this.z,
    required this.controlledFor,
  });

  final Factor factor;
  final String better;
  final String worse;
  final double betterRate;
  final double worseRate;
  final int questions;
  final int days;
  final int strata; // karşılaştırmanın tekrarlandığı katman sayısı
  final double z;
  final String controlledFor; // "aynı ders ve aynı kaynak"

  double get gap => betterRate - worseRate;

  String get sentence {
    final b = (betterRate * 100).round(), w = (worseRate * 100).round();
    final pts = (gap * 100).round();
    return switch (factor) {
      Factor.timeOfDay => '$better çözdüğün sorularda doğruluğun %$b, $worse %$w ($pts puan fark).',
      Factor.dayType => '$better doğruluğun %$b, $worse %$w ($pts puan fark).',
      Factor.pace => '$better çözdüğünde doğruluğun %$b, $worse çözdüğünde %$w ($pts puan fark).',
      Factor.sessionLength => '$better oturumlarda doğruluğun %$b, $worse oturumlarda %$w ($pts puan fark).',
      Factor.source => '$worse kaynağında doğruluğun %$w, $better kaynağında %$b: $worse senin için daha zor ($pts puan).',
      Factor.topic => '$worse konusunda doğruluğun %$w, $better konusunda %$b ($pts puan fark). Önce $worse.',
      Factor.period => better == 'Son dönem'
          ? 'İlerliyorsun: son dönemde doğruluğun %$b, ilk dönemde %$w ($pts puan artış).'
          : 'Dikkat: son dönemde doğruluğun %$w, ilk dönemde %$b ($pts puan düşüş).',
    };
  }

  String get evidence => '$controlledFor karşılaştırıldı; $days günde $questions soru'
      '${strata > 1 ? ', $strata ayrı grupta aynı yönde' : ''}.';
}

class DeepAnalysis {
  const DeepAnalysis({required this.findings, required this.questions, required this.days});
  final List<Finding> findings;
  final int questions;
  final int days;
}

/// Güvenilirlik eşikleri: az veriyle yorum yapılmaz.
class AnalysisThresholds {
  const AnalysisThresholds({
    this.minQuestions = 30,
    this.minDays = 3,
    this.minGap = 0.08,
    this.minZ = 2.0,
    this.minAgreement = 2 / 3,
  });

  final int minQuestions; // bir grupta en az soru
  final int minDays; // bir grupta en az farklı gün (tekrar şartı)
  final double minGap; // en az fark (oran)
  final double minZ; // istatistiksel güven (≈ %95)
  final double minAgreement; // birden çok katmanda aynı yön oranı
}

String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

String? _timeOfDay(DateTime? at) {
  if (at == null) return null;
  final h = at.hour;
  if (h >= 5 && h < 12) return 'Sabah';
  if (h >= 12 && h < 17) return 'Öğleden sonra';
  if (h >= 17 && h < 21) return 'Akşam';
  return 'Gece';
}

String? _sessionLength(int? minutes) {
  if (minutes == null || minutes <= 0) return null;
  if (minutes < 45) return 'Kısa (45 dk altı)';
  if (minutes <= 90) return 'Orta (45–90 dk)';
  return 'Uzun (90 dk üstü)';
}

/// Tüm gözlemlerden bulgular. Her etken için diğer koşullar sabit tutulur:
/// karşılaştırma yalnızca aynı katmanın (ör. aynı ders ve kaynak) içinde yapılır.
DeepAnalysis analyze(List<Observation> all, {AnalysisThresholds t = const AnalysisThresholds()}) {
  final obs = [for (final o in all) if (o.total > 0) o];

  // Hız: dersin kendi ortanca süresine göre (dersler arası fark karışmasın).
  final medians = <String, double>{};
  final bySubject = <String, List<double>>{};
  for (final o in obs) {
    final s = o.secondsPerQuestion;
    if (s != null && s > 0) (bySubject[o.subject] ??= []).add(s);
  }
  for (final e in bySubject.entries) {
    final v = e.value..sort();
    medians[e.key] = v[v.length ~/ 2];
  }
  String? pace(Observation o) {
    final s = o.secondsPerQuestion, m = medians[o.subject];
    if (s == null || m == null || s <= 0) return null;
    if (s < m * 0.8) return 'Hızlı';
    if (s > m * 1.25) return 'Yavaş';
    return 'Normal hızda';
  }

  // Dönem: her ders+kaynak için tarih sırasına göre ilk yarı / son yarı.
  final periodOf = <Observation, String>{};
  final streams = <String, List<Observation>>{};
  for (final o in obs) {
    (streams['${o.subject}|${o.source}'] ??= []).add(o);
  }
  for (final list in streams.values) {
    list.sort((a, b) => a.day.compareTo(b.day));
    final days = {for (final o in list) _dayKey(o.day)}.toList();
    if (days.length < 2 * t.minDays) continue;
    final cut = days[days.length ~/ 2];
    var secondHalf = false;
    for (final o in list) {
      if (_dayKey(o.day) == cut) secondHalf = true;
      periodOf[o] = secondHalf ? 'Son dönem' : 'İlk dönem';
    }
  }

  String? levelOf(Factor f, Observation o) => switch (f) {
        Factor.timeOfDay => _timeOfDay(o.at),
        Factor.dayType => o.at == null ? null : (o.at!.weekday >= 6 ? 'Hafta sonu' : 'Hafta içi'),
        Factor.pace => pace(o),
        Factor.sessionLength => _sessionLength(o.sessionMinutes),
        Factor.source => o.source,
        Factor.topic => o.topic,
        Factor.period => periodOf[o],
      };

  // Hangi koşullar sabit tutulur.
  (String?, String) contextOf(Factor f, Observation o) => switch (f) {
        Factor.timeOfDay || Factor.dayType || Factor.pace => ('${o.subject}|${o.source}', 'Aynı ders ve aynı kaynakta'),
        Factor.sessionLength => (o.subject, 'Aynı derste'),
        Factor.source => o.topic == null ? (null, '') : ('${o.subject}|${o.topic}', 'Aynı ders ve aynı konuda'),
        Factor.topic => ('${o.subject}|${o.source}', 'Aynı ders ve aynı kaynakta'),
        Factor.period => ('${o.subject}|${o.source}|${pace(o)}', 'Aynı ders, aynı kaynak ve aynı hızda'),
      };

  final findings = <Finding>[];
  for (final f in Factor.values) {
    // katman → düzey → hücre
    final cells = <String, Map<String, _Cell>>{};
    var controlled = '';
    for (final o in obs) {
      final level = levelOf(f, o);
      if (level == null) continue;
      final (ctx, label) = contextOf(f, o);
      if (ctx == null) continue;
      controlled = label;
      ((cells[ctx] ??= {})[level] ??= _Cell()).add(o);
    }
    final best = _bestContrast(f, cells, t, controlled);
    if (best != null) findings.add(best);
  }
  findings.sort((a, b) => b.z.abs().compareTo(a.z.abs()));
  return DeepAnalysis(
    findings: findings,
    questions: obs.fold(0, (s, o) => s + o.total),
    days: {for (final o in obs) _dayKey(o.day)}.length,
  );
}

class _Cell {
  int correct = 0, total = 0;
  final days = <String>{};
  void add(Observation o) {
    correct += o.correct;
    total += o.total;
    days.add(_dayKey(o.day));
  }

  double get rate => total == 0 ? 0 : correct / total;
}

/// Katman içi farkların ağırlıklı birleşimi; en güçlü güvenilir düzey çifti.
Finding? _bestContrast(Factor f, Map<String, Map<String, _Cell>> cells, AnalysisThresholds t, String controlled) {
  final levels = {for (final m in cells.values) ...m.keys}.toList();
  Finding? best;
  for (var i = 0; i < levels.length; i++) {
    for (var j = i + 1; j < levels.length; j++) {
      final a = levels[i], b = levels[j];
      var wSum = 0.0, diffSum = 0.0, varSum = 0.0;
      var aCorrect = 0, aTotal = 0, bCorrect = 0, bTotal = 0, strata = 0, positive = 0;
      final days = <String>{};
      for (final m in cells.values) {
        final ca = m[a], cb = m[b];
        if (ca == null || cb == null) continue;
        if (ca.total < t.minQuestions || cb.total < t.minQuestions) continue;
        if (ca.days.length < t.minDays || cb.days.length < t.minDays) continue;
        final w = 2 / (1 / ca.total + 1 / cb.total); // harmonik ağırlık
        final d = ca.rate - cb.rate;
        final v = ca.rate * (1 - ca.rate) / ca.total + cb.rate * (1 - cb.rate) / cb.total;
        wSum += w;
        diffSum += w * d;
        varSum += w * w * v;
        strata++;
        if (d > 0) positive++;
        aCorrect += ca.correct;
        aTotal += ca.total;
        bCorrect += cb.correct;
        bTotal += cb.total;
        days
          ..addAll(ca.days)
          ..addAll(cb.days);
      }
      if (strata == 0 || wSum == 0) continue;
      final diff = diffSum / wSum;
      final se = math.sqrt(varSum) / wSum;
      if (se == 0) continue;
      final z = diff / se;
      final agree = (diff > 0 ? positive : strata - positive) / strata;
      if (diff.abs() < t.minGap || z.abs() < t.minZ) continue;
      if (strata > 1 && agree < t.minAgreement) continue;
      final aBetter = diff > 0;
      final candidate = Finding(
        factor: f,
        better: aBetter ? a : b,
        worse: aBetter ? b : a,
        betterRate: aBetter ? aCorrect / aTotal : bCorrect / bTotal,
        worseRate: aBetter ? bCorrect / bTotal : aCorrect / aTotal,
        questions: aTotal + bTotal,
        days: days.length,
        strata: strata,
        z: z.abs(),
        controlledFor: controlled,
      );
      if (best == null || candidate.z > best.z) best = candidate;
    }
  }
  return best;
}
