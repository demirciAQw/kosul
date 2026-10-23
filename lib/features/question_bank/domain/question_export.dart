import 'dart:convert';

import '../../../core/export/zip_writer.dart';
import '../data/question_card_json.dart';
import 'question_card.dart';

/// Dışa aktarılan dosyaların adı nasıl kurulsun.
enum ExportNaming {
  tags('Etiketlerle'), // TYT_Matematik_Türev_Test_5_S7_Yanlış
  date('Tarihle'), // 2026-10-19_TYT_Matematik_Yanlış
  sequence('Sıra numarasıyla'); // 001_TYT_Matematik

  const ExportNaming(this.label);
  final String label;
}

class QuestionExportOptions {
  const QuestionExportOptions({
    this.questionPhotos = true,
    this.solutionPhotos = true,
    this.table = true,
    this.fullData = false,
    this.folderBySubject = true,
    this.naming = ExportNaming.tags,
  });

  final bool questionPhotos;
  final bool solutionPhotos;

  /// Etiket tablosu (CSV; Excel ve Google E-Tablolar açar).
  final bool table;

  /// Tüm alanlarla JSON (başka bir uygulamaya ya da yedeğe).
  final bool fullData;

  /// Fotoğrafları derslere göre klasörle.
  final bool folderBySubject;
  final ExportNaming naming;

  bool get isEmpty => !questionPhotos && !solutionPhotos && !table && !fullData;

  QuestionExportOptions copyWith({
    bool? questionPhotos,
    bool? solutionPhotos,
    bool? table,
    bool? fullData,
    bool? folderBySubject,
    ExportNaming? naming,
  }) =>
      QuestionExportOptions(
        questionPhotos: questionPhotos ?? this.questionPhotos,
        solutionPhotos: solutionPhotos ?? this.solutionPhotos,
        table: table ?? this.table,
        fullData: fullData ?? this.fullData,
        folderBySubject: folderBySubject ?? this.folderBySubject,
        naming: naming ?? this.naming,
      );
}

/// Pakete girecek bir medya dosyası: ZIP içindeki ad ve telefondaki göreli yol.
class ExportMedia {
  const ExportMedia(this.zipName, this.mediaPath);
  final String zipName;
  final String mediaPath;
}

class QuestionExportPlan {
  const QuestionExportPlan({required this.media, this.table, this.json});
  final List<ExportMedia> media;
  final String? table;
  final String? json;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _ext(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 || dot < path.lastIndexOf('/') ? '.jpg' : path.substring(dot);
}

/// CSV alanı: ayraç, tırnak ya da satır sonu varsa tırnak içine alınır.
String _cell(Object? v) {
  final s = v?.toString() ?? '';
  return (s.contains(';') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Kartlardan paket planı. [topicOf] kartın konu adını verir (MEB konusu ya da
/// kazanım); yoksa null.
QuestionExportPlan planQuestionExport(
  List<QuestionCard> cards,
  QuestionExportOptions o, {
  required String? Function(QuestionCard) topicOf,
}) {
  final media = <ExportMedia>[];
  final rows = <List<Object?>>[];
  for (final (i, c) in cards.indexed) {
    final topic = topicOf(c);
    final where = c.testLabel ?? c.sourceName;
    final base = switch (o.naming) {
      ExportNaming.tags => safeFileName([
          c.subject,
          if (topic != null) topic,
          where,
          if (c.questionNo != null) 'S${c.questionNo}',
          c.status.label,
        ].join(' ')),
      ExportNaming.date => safeFileName('${_isoDate(c.createdAt)} ${c.subject} ${c.status.label}'),
      ExportNaming.sequence => safeFileName('${(i + 1).toString().padLeft(3, '0')} ${c.subject}'),
    };
    final folder = o.folderBySubject ? '${safeFileName(c.subject)}/' : '';
    String? qName, sName;
    final q = c.questionImage, s = c.solutionImage;
    if (o.questionPhotos && q != null) {
      qName = '$folder$base${_ext(q)}';
      media.add(ExportMedia(qName, q));
    }
    if (o.solutionPhotos && s != null) {
      sName = '$folder${base}_cozum${_ext(s)}';
      media.add(ExportMedia(sName, s));
    }
    rows.add([
      i + 1,
      qName,
      sName,
      c.status.label,
      c.subject,
      topic,
      c.sourceName,
      c.testLabel,
      c.questionNo,
      c.correctAnswer,
      c.givenAnswer,
      c.reasonText,
      c.difficulty,
      c.isStarred ? 'evet' : '',
      _isoDate(c.createdAt),
      c.note,
    ]);
  }
  String? table;
  if (o.table) {
    const header = [
      'Sıra', 'Soru dosyası', 'Çözüm dosyası', 'Durum', 'Ders', 'Konu', 'Kaynak', 'Test', 'Soru no', //
      'Doğru cevap', 'Senin cevabın', 'Neden', 'Zorluk', 'Yıldızlı', 'Eklenme', 'Not',
    ];
    table = [header, ...rows].map((r) => r.map(_cell).join(';')).join('\r\n');
  }
  final json = o.fullData
      ? const JsonEncoder.withIndent('  ').convert({
          'format': 'kocum.questions',
          'version': 1,
          'cards': [for (final c in cards) c.toJson()],
        })
      : null;
  return QuestionExportPlan(media: media, table: table, json: json);
}
