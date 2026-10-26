import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/ocr/auto_tag_providers.dart';
import 'package:kocum/features/ocr/domain/auto_tags.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/domain/question_grouping.dart';

QuestionCard _card(String id, {String? topicText}) => QuestionCard(
      id: id,
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.book,
      sourceName: 'Kitap',
      subject: 'AYT Matematik',
      difficulty: 5,
      createdAt: DateTime(2026, 10, 1),
      topicText: topicText,
    );

void main() {
  final lex = TopicLexicon.fromJson(
      jsonDecode(File('assets/meb/konu_sozlugu.json').readAsStringSync()) as Map<String, dynamic>);
  String? topic(String subject, String text) => pickTopic(topicScores(lex, subject, text)).topic;

  test('örnek sorularda konu (Python prototipiyle aynı)', () {
    expect(
        topic('TYT Kimya',
            "Aynı koşullarda X bileşiğinin kararlı elementlerinden oluşumu ile ilgili • 1 mol X gazının oluşumu "
                "sırasında açığa çıkan enerji 100 kJ'dür. • 2 mol X gazının oluşumu sırasında açığa çıkan enerji 200 "
                "kJ'dür. • 1 mol X sıvısının oluşumu sırasında açığa çıkan enerji 125 kJ'dür. Verilen bilgilerden yola "
                'çıkılarak entalpi değişimiyle ilgili I. Madde miktarına bağlıdır. II. Maddenin fiziksel hâline '
                'bağlıdır. III. Katalizöre bağlı değildir. çıkarımlarından hangileri yapılabilir?'),
        'Kimyasal Tepkimelerde Enerji');
    expect(topic('TYT Türkçe', 'Okumak, insanın kendi iç dünyasına açılan bir kapıdır... '
        'Bu parçada asıl anlatılmak istenen aşağıdakilerden hangisidir?'), 'Paragraf');
    expect(topic('TYT Fizik', 'Sürtünmesiz yatay düzlemde durmakta olan 2 kg kütleli cisme 10 N büyüklüğünde '
        'yatay kuvvet uygulanıyor. Cismin ivmesi kaç m/s² olur?'), 'Kuvvet ve Hareket');
    expect(topic('AYT Matematik', "f(x) = x³ − 3x fonksiyonunun türevi f'(x) olduğuna göre, f fonksiyonunun "
        'azalan olduğu aralık hangisidir?'), 'Türev');
  });

  test('kararsızsa konu verilmez, olası iki konu söylenir', () {
    final p = pickTopic(topicScores(
        lex,
        'AYT Matematik',
        'ABE ve BCD dik üçgen, [AB] ⊥ [AE], [BE] ⊥ [BD], [BC] ⊥ [CD], m(AEB) = α° ve |AB| = 2·|BD| olduğuna '
            'göre, sarı renkli üçgenin alanının mavi renkli üçgenin alanına oranının α türünden değeri '
            'aşağıdakilerden hangisidir? 4 / sin²α 4 / cos²α 4·sin²α 4·cos²α 4·tan²α'));
    expect(p.topic, isNull);
    expect(p.candidates, ['Trigonometri', 'Üçgenler']);
  });

  test('ders ailesi ve kısa kelimelerin tam eşleşmesi', () {
    expect(lex.familiesOf('AYT Matematik'), ['mat', 'geo']);
    expect(lex.familiesOf('TYT Edebiyat'), ['edb', 'tur']);
    // "sin" kısa: "sınıf", "sinir" ile eşleşmez.
    expect(topicScores(lex, 'AYT Matematik', 'Bu sınıfta sinirli bir öğrenci var').where((s) => s.$1 == 'Trigonometri'),
        isEmpty);
  });

  test('soru türleri', () {
    expect(
      questionTypes(
        text: 'Grafiğe göre aşağıdakilerden hangisi söylenemez?',
        prompt: 'Grafiğe göre aşağıdakilerden hangisi söylenemez?',
        figureKinds: const ['chart'],
        hasStatements: false,
        stemWords: 70,
      ),
      ['Paragraf', 'Grafik yorumlama', 'Olumsuz kök'],
    );
  });

  test('gruplama: konusu olmayan soru elle yazılan ya da otomatik konuyla', () {
    final cards = [_card('a'), _card('b', topicText: 'türev'), _card('c')];
    final fallback = fallbackTopicsFor(cards, {
      'a': const AutoTags(topic: 'İntegral'),
      'b': const AutoTags(topic: 'Limit ve Süreklilik'), // elle yazılan öncelikli
    });
    expect(fallback, {'a': 'İntegral (otomatik)', 'b': 'Türev'});
    final groups = groupQuestions(cards, GroupBy.topic,
        curriculum: const {}, bookTitles: const {}, fallbackTopics: fallback);
    expect(groups.map((g) => g.title), ['İntegral (otomatik)', 'Türev', noTopicTitle]);
  });
}
