import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/dashboard/dashboard_providers.dart';
import 'package:kocum/features/dashboard/domain/stem_analysis.dart';
import 'package:kocum/features/ocr/domain/ocr.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';

StemSample _s(String prompt, {MistakeReason? reason, QuestionStatus status = QuestionStatus.wrong}) =>
    StemSample(prompt: prompt, status: status, reason: reason);

void main() {
  test('kök türleri: olumsuz, öncüllü, "en …", hesap, olumlu', () {
    const cases = {
      'Bu parçada aşağıdakilerden hangisine değinilmemiştir?': StemKind.negative,
      'Buna göre aşağıdakilerden hangisi söylenemez?': StemKind.negative,
      'Aşağıdakilerden hangisi yanlıştır?': StemKind.negative,
      'Hangisi bu düşünceye uygun değildir?': StemKind.negative,
      'Buna göre x kaç olamaz?': StemKind.negative, // olumsuz, hesaptan önce gelir
      'Bu parçanın konusu aşağıdakilerden hangisi olmaz?': StemKind.negative,
      'çıkarımlarından hangileri yapılabilir?': StemKind.premise,
      'Buna göre x en az kaçtır?': StemKind.superlative,
      "x'in alabileceği kaç farklı tam sayı değeri vardır?": StemKind.quantity,
      'Bu bilgilere göre ürünün değeri nedir?': StemKind.positive, // "değeri" olumsuz değil
      'Bu parçada asıl anlatılmak istenen nedir?': StemKind.positive,
    };
    for (final e in cases.entries) {
      expect(classifyStem(e.key), e.value, reason: e.key);
    }
    expect(classifyStem('Hangisi doğrudur?', hasStatements: true), StemKind.premise);
  });

  test('açık ara eğilim: olumsuz köklerde dikkatsizlik', () {
    final samples = [
      for (var i = 0; i < 10; i++)
        _s('Aşağıdakilerden hangisi söylenemez?',
            reason: i < 8 ? MistakeReason.carelessness : MistakeReason.knowledgeGap),
      for (var i = 0; i < 12; i++)
        _s('Buna göre x kaçtır?', reason: i < 2 ? MistakeReason.carelessness : MistakeReason.knowledgeGap),
    ];
    final r = analyzeStems(samples);
    expect(r.hasClearTrend, isTrue);
    expect(r.trends.first.kind, StemKind.negative);
    expect(r.trends.first.z, closeTo(2.971, 0.01));
    expect(r.verdict, startsWith('Açık ara bir eğilim var.'));
    expect(r.trends.first.text, contains('%80 (8/10)'));
    // Ayna bulgu ("hesap köklerinde düşük") raporlanmaz.
    expect(r.trends.where((t) => t.kind == StemKind.quantity), isEmpty);
  });

  test('fark küçükse eğilim yok; veri azsa bunu söyler', () {
    final even = [
      for (var i = 0; i < 10; i++)
        _s('Hangisi yanlıştır?', reason: i < 3 ? MistakeReason.carelessness : MistakeReason.knowledgeGap),
      for (var i = 0; i < 12; i++)
        _s('Hangisi doğrudur?', reason: i < 4 ? MistakeReason.carelessness : MistakeReason.knowledgeGap),
    ];
    expect(analyzeStems(even).verdict, startsWith('Açık ara bir eğilim yok'));
    expect(analyzeStems([for (var i = 0; i < 5; i++) _s('Hangisi yanlıştır?')]).verdict,
        startsWith('Henüz yeterli veri yok'));
  });

  test('basit kelime benzerliğiyle tekrar eden kalıplar', () {
    final r = analyzeStems([
      _s('Bu parçada aşağıdakilerden hangisine değinilmemiştir?', reason: MistakeReason.carelessness),
      _s('Paragrafta aşağıdakilerden hangisine değinilmemiştir?'),
      _s('Bu parçada aşağıdakilerden hangisine değinilmemiştir?', status: QuestionStatus.blank),
      _s('Buna göre x kaçtır?'),
    ]);
    expect(r.templates, hasLength(1));
    final t = r.templates.single;
    expect((t.count, t.wrong, t.blank, t.careless), (3, 2, 1, 1));
  });

  test('okuma kaydından asıl sorunun soru cümlesi', () {
    final r = OcrRecord(
      id: 'question:a',
      ownerType: 'question',
      ownerId: 'a',
      imagePath: 'q.webp',
      status: 'done',
      processedAt: DateTime(2026),
      structure: {
        'primary': 1,
        'questions': [
          {'prompt': 'kesik soru?', 'statements': []},
          {
            'prompt': 'çıkarımlarından hangileri yapılabilir?',
            'statements': [
              {'label': 'I', 'text': 'x'},
            ],
          },
        ],
      },
    );
    final p = questionPromptOf(r)!;
    expect(p.prompt, 'çıkarımlarından hangileri yapılabilir?');
    expect(p.hasStatements, isTrue);
  });
}
