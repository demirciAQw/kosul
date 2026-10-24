import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/dashboard/domain/deep_analysis.dart';

/// [days] gün boyunca, verilen saatte, [n] soruluk ve [rate] doğruluklu oturumlar.
List<Observation> _runs({
  required int days,
  required int hour,
  required double rate,
  int n = 20,
  String subject = 'AYT Matematik',
  String source = 'Kitap A',
  String? topic,
  double? secs,
  int dayOffset = 0,
}) =>
    [
      for (var d = 0; d < days; d++)
        Observation(
          at: DateTime(2026, 10, 1 + d + dayOffset, hour),
          day: DateTime(2026, 10, 1 + d + dayOffset),
          subject: subject,
          source: source,
          topic: topic,
          correct: (n * rate).round(),
          wrong: n - (n * rate).round(),
          blank: 0,
          secondsPerQuestion: secs,
          sessionMinutes: 60,
          sessionKey: '$subject$source$hour$d$dayOffset',
        ),
    ];

void main() {
  test('az veriyle yorum yapmaz', () {
    final obs = [..._runs(days: 2, hour: 9, rate: 0.9), ..._runs(days: 2, hour: 20, rate: 0.4)];
    final a = analyze(obs);
    expect(a.findings, isEmpty); // 2 gün < 3 gün şartı
    expect(a.questions, 80);
  });

  test('aynı ders ve kaynakta tekrarlanan saat farkını bulur', () {
    final obs = [
      ..._runs(days: 4, hour: 9, rate: 0.85),
      ..._runs(days: 4, hour: 20, rate: 0.55, dayOffset: 10),
    ];
    final f = analyze(obs).findings.firstWhere((x) => x.factor == Factor.timeOfDay);
    expect(f.better, 'Sabah');
    expect(f.worse, 'Akşam');
    expect(f.gap, closeTo(0.30, 0.02));
    expect(f.days, 8);
    expect(f.controlledFor, contains('Aynı ders ve aynı kaynakta'));
  });

  test('dersler arası fark saat etkisi sanılmaz (karıştırıcı kontrol)', () {
    // Sabahları hep kolay ders, akşamları hep zor ders: aynı ders içinde saat karşılaştırılamaz.
    final obs = [
      ..._runs(days: 5, hour: 9, rate: 0.9, subject: 'TYT Türkçe'),
      ..._runs(days: 5, hour: 20, rate: 0.5, subject: 'AYT Fizik'),
    ];
    expect(analyze(obs).findings.where((x) => x.factor == Factor.timeOfDay), isEmpty);
  });

  test('gruplar çelişirse yorum yapmaz', () {
    // Kitap A'da sabah iyi, Kitap B'de akşam iyi: tutarlı bir saat etkisi yok.
    final obs = [
      ..._runs(days: 4, hour: 9, rate: 0.85, source: 'Kitap A'),
      ..._runs(days: 4, hour: 20, rate: 0.55, source: 'Kitap A', dayOffset: 10),
      ..._runs(days: 4, hour: 9, rate: 0.55, source: 'Kitap B', dayOffset: 20),
      ..._runs(days: 4, hour: 20, rate: 0.85, source: 'Kitap B', dayOffset: 30),
    ];
    expect(analyze(obs).findings.where((x) => x.factor == Factor.timeOfDay), isEmpty);
  });

  test('aynı kaynakta zayıf konu ve hızlı çözümün etkisi', () {
    final obs = [
      ..._runs(days: 4, hour: 17, rate: 0.85, topic: 'Türev', secs: 60),
      ..._runs(days: 4, hour: 17, rate: 0.5, topic: 'İntegral', secs: 60, dayOffset: 10),
    ];
    final topic = analyze(obs).findings.firstWhere((x) => x.factor == Factor.topic);
    expect(topic.worse, 'İntegral');
    expect(topic.sentence, contains('Önce İntegral'));
  });
}
