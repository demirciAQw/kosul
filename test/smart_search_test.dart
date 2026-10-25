import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kocum/features/question_bank/data/search_store.dart';
import 'package:kocum/features/question_bank/domain/question_card.dart';
import 'package:kocum/features/question_bank/domain/smart_search.dart';

QuestionCard _c(String id, String topic, String subject, String source, {MistakeReason? reason, String? note}) =>
    QuestionCard(
      id: id,
      status: QuestionStatus.wrong,
      origin: QuestionOrigin.book,
      sourceName: source,
      subject: subject,
      difficulty: 5,
      createdAt: DateTime(2026, 10, 1),
      topicText: topic,
      reason: reason,
      note: note,
    );

List<SearchField> _fields(QuestionCard c) => [
      SearchField(c.topicText!, fieldWeights.topic),
      SearchField(c.subject, fieldWeights.subject),
      SearchField(c.sourceName, fieldWeights.source),
      if (c.reasonText != null) SearchField(c.reasonText!, fieldWeights.reason),
      if (c.note != null) SearchField(c.note!, fieldWeights.note),
    ];

void main() {
  final cards = [
    _c('turev', 'Türev', 'AYT Matematik', 'Bilgi Sarmal', reason: MistakeReason.carelessness),
    _c('kural', 'Türev Kuralları', 'AYT Matematik', 'Orijinal', note: 'zincir kuralı'),
    _c('integral', 'İntegral', 'AYT Matematik', 'Bilgi Sarmal', reason: MistakeReason.carelessness),
    _c('vektor', 'Vektörler', 'TYT Fizik', 'Bilgi Sarmal Fizik'),
    _c('paragraf', 'Paragrafta Yardımcı Düşünce', 'TYT Türkçe', '345 Paragraf'),
  ];
  List<String> ids(String q) => smartSearch(cards, q, _fields).cards.map((c) => c.id).toList();

  test('düzenleme uzaklığı: bitişik harf yer değişimi tek hata', () {
    expect(editDistance('turev', 'tuerv', 3), 1);
    expect(editDistance('integarl', 'integral', 3), 1);
    expect(editDistance('abc', 'xyz', 1), 2); // sınırı aşınca cutoff + 1
  });

  test('yazım hataları düzelir', () {
    expect(ids('türv').take(2).toSet(), {'turev', 'kural'});
    expect(ids('tüerv').toSet(), {'turev', 'kural'});
    expect(ids('vectorler'), ['vektor']);
    expect(ids('integarl'), ['integral']);
    expect(ids('paragrf'), ['paragraf']);
    expect(ids('xyzq'), isEmpty);
  });

  test('sıralama: tam alan önce; tüm kelimeleri eşleşen önce; tek kelime eşleşen de listede', () {
    expect(ids('türev').first, 'turev'); // konusu tam "Türev"
    final two = ids('turev kurali');
    expect(two.first, 'kural');
    expect(two, contains('turev')); // yalnızca bir kelimesi eşleşse de listelenir
  });

  test('bunu mu demek istedin', () {
    expect(smartSearch(cards, 'integarl', _fields).suggestion, 'İntegral');
    expect(smartSearch(cards, 'türev', _fields).suggestion, isNull);
  });

  test('arama geçmişi: en yeni başta, tekrarsız', () {
    var h = pushHistory(const [], 'türev');
    h = pushHistory(h, 'vektör');
    h = pushHistory(h, 'TÜREV');
    expect(h, ['TÜREV', 'vektör']);
  });

  test('veri seti: her olay bir JSON satırı', () async {
    final dir = await Directory.systemTemp.createTemp('kocum_log');
    addTearDown(() => dir.delete(recursive: true));
    final log = SearchLog(baseDir: () async => dir);
    await log.append({'type': 'search', 'query': 'türv'});
    await log.append({'type': 'open', 'rank': 1});
    final lines = await (await log.file()).readAsLines();
    expect(lines.map((l) => jsonDecode(l)['type']), ['search', 'open']);
  });
}
