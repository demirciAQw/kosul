import '../../../core/text/turkish_text.dart';
import '../../dashboard/domain/stem_analysis.dart';
import 'ocr.dart';

/// Otomatik etiketler: okunan soru metninden konu ve soru türü. Model
/// gerektirmez; anında, her telefonda çalışır. Kurallar Python prototipinde
/// örnek sorularla denenmiştir (assets/meb/konu_sozlugu.json ile aynı sözlük).

/// Konu sözlüğü (assets/meb/konu_sozlugu.json).
class TopicLexicon {
  TopicLexicon({required this.subjects, required this.families});

  /// Ders adında geçen parça → ders aileleri ("matematik" → mat, geo).
  final Map<String, List<String>> subjects;

  /// Aile → konu → anahtar kelimeler (katlanmış).
  final Map<String, Map<String, List<String>>> families;

  final _patterns = <String, RegExp>{};

  factory TopicLexicon.fromJson(Map<String, dynamic> j) => TopicLexicon(
        subjects: {
          for (final e in (j['subjects'] as Map).entries)
            e.key as String: [for (final f in e.value as List) f as String],
        },
        families: {
          for (final f in (j['families'] as Map).entries)
            f.key as String: {
              for (final t in (f.value as Map).entries)
                t.key as String: [for (final k in t.value as List) k as String],
            },
        },
      );

  /// 4 harf ve üstü son kelime ek alabilir (türev → türevinin); kısalar tam eşleşir.
  RegExp patternOf(String keyword) => _patterns.putIfAbsent(keyword, () {
        final last = keyword.split(' ').last;
        return RegExp('(?<![a-z0-9])${RegExp.escape(keyword)}${last.length >= 4 ? '[a-z0-9]*' : ''}(?![a-z0-9])');
      });

  List<String> familiesOf(String subject) {
    final n = foldForTags(subject);
    final out = <String>[];
    for (final e in subjects.entries) {
      if (n.contains(e.key)) {
        for (final f in e.value) {
          if (!out.contains(f)) out.add(f);
        }
      }
    }
    return out.isEmpty ? families.keys.toList() : out;
  }
}

/// Katlanmış, yalnızca harf-rakam ve tek boşluk ("Türevinin x'i" → "turevinin x i").
String foldForTags(String s) =>
    normalizeTr(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().replaceAll(RegExp(r' +'), ' ');

/// Konu puanları (büyükten küçüğe; eşitse ada göre). Her kelime en fazla 2 kez,
/// boşluklu ifadeler iki kat sayılır.
List<(String, int)> topicScores(TopicLexicon lex, String subject, String text) {
  final t = foldForTags(text);
  final scores = <String, int>{};
  for (final f in lex.familiesOf(subject)) {
    for (final topic in lex.families[f]!.entries) {
      var s = 0;
      for (final k in topic.value) {
        final c = lex.patternOf(k).allMatches(t).length;
        s += (c > 2 ? 2 : c) * (k.contains(' ') ? 2 : 1);
      }
      if (s > 0) scores[topic.key] = (scores[topic.key] ?? 0) + s;
    }
  }
  return scores.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
}

/// Kesin konu (en az 2 puan ve ikinciden 1,5 kat önde) ya da olası iki konu.
({String? topic, List<String> candidates}) pickTopic(List<(String, int)> scores) {
  if (scores.isEmpty) return (topic: null, candidates: const []);
  final best = scores.first;
  final second = scores.length > 1 ? scores[1].$2 : 0;
  if (best.$2 >= 2 && best.$2 >= 1.5 * second) return (topic: best.$1, candidates: const []);
  return (topic: null, candidates: [for (final s in scores.take(2)) if (s.$2 >= 2) s.$1]);
}

final _graphWord = RegExp(r'\bgrafi');
final _tableWord = RegExp(r'\btablo');
final _figureWord = RegExp(r'\bsekil');
final _visualWord = RegExp(r'\bgorsel');
final _experimentWord = RegExp(r'\b(deney|duzenek)');

/// Soru türleri: okuyucunun bulduğu yapı ve şekillerle metinden.
List<String> questionTypes({
  required String text,
  required String prompt,
  required List<String> figureKinds,
  required bool hasStatements,
  required int stemWords,
}) {
  final t = foldForTags(text);
  final kind = prompt.trim().isEmpty ? null : classifyStem(prompt, hasStatements: hasStatements);
  return [
    if (stemWords >= 60) 'Paragraf',
    if (figureKinds.contains('chart') || _graphWord.hasMatch(t)) 'Grafik yorumlama',
    if (figureKinds.contains('table') || _tableWord.hasMatch(t)) 'Tablo',
    if (figureKinds.contains('diagram') || _figureWord.hasMatch(t)) 'Şekilli',
    if (figureKinds.contains('photo') || _visualWord.hasMatch(t)) 'Görsel',
    if (hasStatements || kind == StemKind.premise) 'Öncüllü',
    if (kind == StemKind.negative) 'Olumsuz kök',
    if (kind == StemKind.quantity) 'Hesap',
    if (_experimentWord.hasMatch(t)) 'Deney',
  ];
}

class AutoTags {
  const AutoTags({this.topic, this.candidates = const [], this.types = const [], this.curriculumId});
  final String? topic; // kesin konu
  final List<String> candidates; // kesin değilse olası iki konu
  final List<String> types;
  final String? curriculumId; // konu MEB ağacında varsa

  bool get isEmpty => topic == null && candidates.isEmpty && types.isEmpty;

  /// Arama ve rapor için tek satır.
  String get summary => [
        if (topic != null) topic!,
        if (topic == null && candidates.isNotEmpty) 'olası: ${candidates.join(' / ')}',
        ...types,
      ].join(', ');

  Map<String, Object?> toJson() => {
        'topic': topic,
        'candidates': candidates,
        'types': types,
        'curriculumId': curriculumId,
      };
}

/// Okuma kaydının asıl sorusu: soru cümlesi, öncül var mı, kök kelime sayısı.
({String prompt, bool hasStatements, int stemWords}) mainQuestionOf(OcrRecord r) {
  final questions = r.structure?['questions'];
  final primary = r.structure?['primary'];
  if (questions is List && primary is int && primary >= 0 && primary < questions.length && questions[primary] is Map) {
    final q = questions[primary] as Map;
    final stem = [for (final p in (q['stem'] as List?) ?? const []) '$p'].join(' ');
    final statements = q['statements'];
    return (
      prompt: (q['prompt'] as String?) ?? '',
      hasStatements: statements is List && statements.isNotEmpty,
      stemWords: stem.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
    );
  }
  final stem = r.parsed?.stem ?? '';
  final ask = stem.split('\n').where((l) => l.contains('?')).toList();
  return (
    prompt: ask.isEmpty ? '' : ask.last,
    hasStatements: false,
    stemWords: stem.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
  );
}

/// Bir sorunun otomatik etiketleri. [curriculumTitles]: o dersin MEB konu
/// adları (katlanmış) → kimlik; konu adı eşleşirse bağlantı önerilir.
AutoTags autoTag({
  required TopicLexicon lexicon,
  required String subject,
  required OcrRecord record,
  Map<String, String> curriculumTitles = const {},
}) {
  final main = mainQuestionOf(record);
  final text = [record.searchable, main.prompt].join(' ');
  final pick = pickTopic(topicScores(lexicon, subject, text));
  return AutoTags(
    topic: pick.topic,
    candidates: pick.candidates,
    types: questionTypes(
      text: text,
      prompt: main.prompt,
      figureKinds: [for (final f in record.figures) '${f['kind']}'],
      hasStatements: main.hasStatements,
      stemWords: main.stemWords,
    ),
    curriculumId: pick.topic == null ? null : curriculumTitles[foldForTags(pick.topic!)],
  );
}
