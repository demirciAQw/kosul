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

/// Gerçek soru metinleri (örnek fotoğraflardan ve tipik sorulardan); beklentiler
/// aynı kurallarla çalışan Python hesabından.
const _profiles = <String, SimilarProfile>{
  'kimya1': SimilarProfile(passage: '1 mol X gazının oluşumu sırasında açığa çıkan enerji 100 kJ\'dür. 2 mol X gazının oluşumunda açığa çıkan enerji 200 kJ\'dür.', prompt: 'Verilen bilgilerden yola çıkılarak entalpi değişimiyle ilgili çıkarımlarından hangileri yapılabilir?', options: 'Yalnız I | II ve III | I ve II | Yalnız II | I, II ve III', given: 'Madde miktarına bağlıdır. Maddenin fiziksel hâline bağlıdır. Katalizöre bağlı değildir.'),
  'kimya2': SimilarProfile(passage: 'Standart koşullarda CH4 gazının yanma tepkimesinde açığa çıkan ısı 890 kJ olarak ölçülmüştür.', prompt: 'Buna göre tepkimenin entalpi değişimi ile ilgili hangisi yanlıştır?', options: 'Tepkime ekzotermiktir | ΔH negatiftir | Ürünlerin entalpisi büyüktür | Isı açığa çıkar | Yanma tepkimesidir'),
  'kimya3': SimilarProfile(passage: 'Ağrı ve Antalya\'da arı suyun kaynaması anında buhar basıncı ve kaynama noktası verilmiştir.', prompt: 'Buna göre verilenlerden hangileri doğrudur?', options: 'Yalnız I | Yalnız II | Yalnız III | I ve III | II ve III', given: 'P2 > P1 dir. P1 = P2 dir. t1 > t2 dir.'),
  'kimya4': SimilarProfile(passage: 'Deniz seviyesinde ve yüksek rakımlı bir yerde suyun kaynama noktası ve buhar basıncı karşılaştırılıyor.', prompt: 'Buna göre kaynama noktası ile ilgili hangisi söylenebilir?', options: 'Yüksek rakımda kaynama noktası düşer | Buhar basıncı değişmez | ...'),
  'edb1': SimilarProfile(passage: 'Eleştiri kesin ölçülere dayanmayı gerekli kılar. Nitelikli bir yorum, gerekçeli bir açıklama yöntemi içinde bütünlüğe varmayı amaçlar. Eleştiri önce bir bilim, bir bilgi davranışıdır.', prompt: 'Bu parçada eleştiri ile ilgili görüşlerini dile getiren birinin aşağıdakilerden hangisini söylemesi beklenmez?', options: 'Eleştirinin inandırıcılığı temellendirilmiş yargılarla artırılır | Bir eleştiri eseri açıklamaya çalışmalıdır | Eleştiri yazısında açık bir dil kullanılmalı | Okuru ikna eden unsur ulaşılan sonuçtur | Eleştiri farklı bakış açıları sunmalıdır'),
  'edb2': SimilarProfile(passage: 'İyi bir eleştirmen, eseri kişisel beğenisiyle değil, sağlam ölçütlerle değerlendirir; eleştiri yazısının amacı okura yol göstermektir.', prompt: 'Bu parçada eleştirmen ile ilgili asıl vurgulanmak istenen nedir?', options: 'Ölçütlere dayanması | Okura yol göstermesi | Kişisel beğeni | ...'),
  'edb3': SimilarProfile(passage: 'Roman, insanın iç dünyasını en derin biçimde yansıtan türdür; karakterlerin ruh hâlleri ayrıntılı işlenir.', prompt: 'Bu parçada asıl anlatılmak istenen aşağıdakilerden hangisidir?', options: 'Romanın iç dünyayı yansıtması | ...'),
  'bio1': SimilarProfile(passage: 'Bir hayvan hücresinde bulunan üç farklı organel K, M ve R olarak şekilde gösterilmiştir.', prompt: 'Bu organeller arasında aşağıdaki özelliklerden hangisine sahip olan yoktur?', options: 'Sitoplazmadan ayrılmasını sağlayan zar sistemi bulundurmama | Hücre dışına salgı gönderme | Yassı keseden oluşma | Kendine özgü DNA | Hücre içinde kanallar oluşturma'),
  'bio2': SimilarProfile(passage: 'Golgi cisimciği, endoplazmik retikulum ve mitokondri organellerinin bazı özellikleri tabloda verilmiştir.', prompt: 'Buna göre bu organellerle ilgili hangisi yanlıştır?', options: 'Mitokondri kendine özgü DNA taşır | Golgi salgı paketler | Endoplazmik retikulum kanal sistemi oluşturur | ...'),
};

String _subject(String id) => id.startsWith('kimya') ? 'TYT Kimya' : (id.startsWith('edb') ? 'TYT Edebiyat' : 'TYT Biyoloji');

void main() {
  test('terimler: kalıp kelimeler, bağlaçlar, Roma rakamları atılır; ilk 5 harf', () {
    expect(termTokens('Buna göre aşağıdakilerden hangisi 125 kJ entalpi değişimidir?'), ['ental', 'degis']);
    expect(termTokens('Bu parçada asıl anlatılmak istenen hangisidir? Yalnız I II ve III'), isEmpty);
    expect(termTokens('entalpisi entalpinin'), ['ental', 'ental']);
  });

  test('aynı konulu çiftler benzer, farklı konulular değil', () {
    final index = SimilarIndex.build(_profiles);
    const pairs = [('kimya1', 'kimya2'), ('kimya3', 'kimya4'), ('edb1', 'edb2'), ('bio1', 'bio2')];
    for (final (a, b) in pairs) {
      expect(index.textSimilarity(a, b).total, greaterThan(0.3), reason: '$a ↔ $b');
    }
    final ids = _profiles.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final pair = (ids[i], ids[j]);
        if (pairs.contains(pair)) continue;
        expect(index.textSimilarity(ids[i], ids[j]).total, lessThan(0.15), reason: '${ids[i]} ↔ ${ids[j]}');
      }
    }
  });

  test('eşleme: benzer sorular aynı grupta, eşi olmayan grupsuz', () {
    final cards = [for (final id in _profiles.keys) _c(id, _subject(id), QuestionStatus.wrong)];
    final groups = similarGroups(cards, _profiles, SimilarIndex.build(_profiles));
    for (final (a, b) in [('kimya1', 'kimya2'), ('kimya3', 'kimya4'), ('edb1', 'edb2'), ('bio1', 'bio2')]) {
      expect(groups[a], isNotNull, reason: a);
      expect(groups[a], groups[b], reason: '$a ↔ $b');
    }
    expect(groups['kimya1'], isNot(groups['kimya3']));
    expect(groups.containsKey('edb3'), isFalse);
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
    const profiles = {
      't': SimilarProfile(
          text: 'entalpi değişimi madde miktarına bağlıdır açığa çıkan enerji kJ',
          topicKey: enerji,
          types: {'Öncüllü'},
          stemKind: 'premise'),
      'a': SimilarProfile(
          text: 'entalpi değişimi fiziksel hâle bağlıdır açığa çıkan enerji',
          topicKey: enerji,
          types: {'Öncüllü'},
          stemKind: 'premise'),
      'b': SimilarProfile(text: 'tepkime entalpisi açığa çıkan enerji', topicKey: enerji),
      'c': SimilarProfile(text: 'entalpi değişimi açığa çıkan enerji', topicKey: enerji),
      'd': SimilarProfile(text: 'avogadro sayısı mol kütle', topicKey: 'mol kavrami'),
    };
    final r = findSimilar(cards.first, cards, profiles, SimilarIndex.build(profiles));
    expect(r.correct.map((m) => m.card.id), ['a']);
    expect(r.mistakes.map((m) => m.card.id), ['b']);
    expect(r.correct.single.reasons, containsAll(['aynı konu', 'ortak tür: Öncüllü', 'aynı kök türü']));
  });
}
