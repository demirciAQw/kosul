import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/domain/similar_questions.dart';

QuestionCard _c(String id, String subject, QuestionStatus status) => QuestionCard(
      id: id,
      status: status,
      origin: QuestionOrigin.book,
      sourceName: 'Kitap',
      subject: subject,
      difficulty: 5,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  test('benzerlik kelimeleri: kalıp kelimeler ve sayılar atılır', () {
    expect(similarityTokens('Buna göre aşağıdakilerden hangisi 125 kJ entalpi değişimidir?'),
        ['entalpi', 'degisimidir']);
  });

  test('aynı metnin benzerliği 1, ortak kelimesizin 0', () {
    final v = tfidfVectors({'a': 'entalpi enerji tepkime', 'b': 'entalpi enerji tepkime', 'c': 'avogadro mol'});
    expect(cosine(v['a']!, v['b']!), closeTo(1, 1e-9));
    expect(cosine(v['a']!, v['c']!), 0);
  });

  test('benzerler: doğrular ve yanlışlar ayrı; başka ders ve alakasız soru yok', () {
    final cards = [
      _c('t', 'TYT Kimya', QuestionStatus.wrong),
      _c('a', 'TYT Kimya', QuestionStatus.correct),
      _c('b', 'TYT Kimya', QuestionStatus.blank),
      _c('c', 'TYT Fizik', QuestionStatus.correct),
      _c('d', 'TYT Kimya', QuestionStatus.correct),
    ];
    const enerji = 'kimyasal tepkimelerde enerji';
    final profiles = {
      't': const SimilarProfile(
          text: 'entalpi değişimi madde miktarına bağlıdır açığa çıkan enerji kJ',
          topicKey: enerji,
          types: {'Öncüllü'},
          stemKind: 'premise'),
      'a': const SimilarProfile(
          text: 'entalpi değişimi fiziksel hâle bağlıdır açığa çıkan enerji',
          topicKey: enerji,
          types: {'Öncüllü'},
          stemKind: 'premise'),
      'b': const SimilarProfile(text: 'tepkime entalpisi açığa çıkan enerji', topicKey: enerji),
      'c': const SimilarProfile(text: 'entalpi değişimi açığa çıkan enerji', topicKey: enerji),
      'd': const SimilarProfile(text: 'avogadro sayısı mol kütle', topicKey: 'mol kavrami'),
    };
    final vectors = tfidfVectors({for (final e in profiles.entries) e.key: e.value.text});
    final r = findSimilar(cards.first, cards, profiles, vectors);
    expect(r.correct.map((m) => m.card.id), ['a']);
    expect(r.mistakes.map((m) => m.card.id), ['b']);
    expect(r.correct.single.reasons, containsAll(['aynı konu', 'ortak tür: Öncüllü', 'aynı kök türü']));
  });
}
