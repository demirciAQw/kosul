import '../../../core/export/zip_writer.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../curriculum/domain/yks.dart';
import '../../library/domain/progress.dart';
import '../../mock_exam/domain/mock_exam.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/domain/question_export.dart' show ExportMedia;
import '../../question_bank/domain/recurrence.dart';

/// Yapay zekâ raporunun kapsamı.
class AiReportOptions {
  const AiReportOptions({this.days = 30, this.subject, this.maxQuestions = 40, this.photos = false});

  /// Son kaç günün soruları (null = hepsi).
  final int? days;

  /// Tek bir ders (null = tüm dersler).
  final String? subject;
  final int maxQuestions;

  /// Soru fotoğrafları da pakete girsin (ZIP).
  final bool photos;

  AiReportOptions copyWith({int? Function()? days, String? Function()? subject, int? maxQuestions, bool? photos}) =>
      AiReportOptions(
        days: days != null ? days() : this.days,
        subject: subject != null ? subject() : this.subject,
        maxQuestions: maxQuestions ?? this.maxQuestions,
        photos: photos ?? this.photos,
      );
}

class AiReport {
  const AiReport({required this.markdown, required this.photos, required this.questionCount});
  final String markdown;
  final List<ExportMedia> photos;
  final int questionCount;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Tablo hücresi: dikey çizgi ve satır sonu tabloyu bozmasın.
String _c(Object? v) => (v?.toString() ?? '').replaceAll('|', '/').replaceAll('\n', ' ').trim();

/// Öğrencinin verisinden, bir yapay zekâ sohbetine yapıştırılacak rapor.
///
/// Yapay zekâya ne yapacağı (eksikleri bul, örüntüleri açıkla, plan öner),
/// verinin özeti, ders ve konu bazında kayıplar, tekrarlayan hatalar,
/// denemeler, kitap ilerlemesi ve son yanlışlar tek bir metinde.
AiReport buildAiReport({
  required List<QuestionCard> cards,
  required Map<String, CurriculumNode> curriculum,
  required List<MockExam> exams,
  required List<BookProgress> books,
  required DateTime now,
  AiReportOptions options = const AiReportOptions(),
}) {
  final o = options;
  final since = o.days == null ? null : now.subtract(Duration(days: o.days!));
  bool inScope(QuestionCard c) =>
      (o.subject == null || c.subject == o.subject) && (since == null || !c.createdAt.isBefore(since));
  final scoped = [for (final c in cards) if (inScope(c)) c];
  final mistakes = [for (final c in scoped) if (c.status != QuestionStatus.correct) c]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final wrong = scoped.where((c) => c.status == QuestionStatus.wrong).length;
  final blank = scoped.where((c) => c.status == QuestionStatus.blank).length;
  final correct = scoped.length - wrong - blank;

  final b = StringBuffer()
    ..writeln('# Koçum öğrenci raporu (${_iso(now)})')
    ..writeln()
    ..writeln('## Senden istediğim')
    ..writeln()
    ..writeln('Sen deneyimli bir YKS koçusun. Aşağıdaki veriler YKS\'ye hazırlanan bir öğrencinin '
        'çalışma uygulamasından alındı. Lütfen:')
    ..writeln('1. En çok net kaybettiren eksik konuları, nedenleriyle birlikte önem sırasına koy (en fazla 5).')
    ..writeln('2. Tekrarlayan hata örüntülerini açıkla: aynı konu, aynı neden, aynı tür soru.')
    ..writeln('3. Her eksik için somut bir çalışma önerisi ver: hangi konuya dön, kaç soru çöz, hangi sırayla.')
    ..writeln('4. Bir haftalık kısa ve gerçekçi bir plan öner (günde en fazla 2-3 saat).')
    ..writeln()
    ..writeln('Verilerde olmayan bir şeyi uydurma; emin olmadığın yerde bunu söyle. '
        '"Neden" sütunu öğrencinin kendi değerlendirmesidir.');
  if (o.photos) {
    b
      ..writeln()
      ..writeln('Soru fotoğrafları "fotograflar/" klasöründe; adları yanlışlar tablosundaki "Dosya" sütunuyla eşleşir.');
  }

  // ── Özet ──
  b
    ..writeln()
    ..writeln('## Özet')
    ..writeln()
    ..writeln('- Kapsam: ${o.days == null ? 'tüm zamanlar' : 'son ${o.days} gün'}, ${o.subject ?? 'tüm dersler'}')
    ..writeln('- Defterdeki soru: ${scoped.length} (yanlış $wrong, boş $blank, doğru $correct)');

  // ── Ders bazında ──
  final bySubject = <String, List<QuestionCard>>{};
  for (final c in mistakes) {
    (bySubject[c.subject] ??= []).add(c);
  }
  if (bySubject.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Ders bazında yanlış ve boşlar')
      ..writeln()
      ..writeln('| Ders | Yanlış | Boş | En sık neden |')
      ..writeln('|---|---|---|---|');
    final ordered = bySubject.keys.toList()..sort((x, y) => bySubject[y]!.length.compareTo(bySubject[x]!.length));
    for (final s in ordered) {
      final list = bySubject[s]!;
      final reasons = <MistakeReason, int>{};
      for (final c in list) {
        final r = c.reason;
        if (r != null) reasons[r] = (reasons[r] ?? 0) + 1;
      }
      final top = reasons.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
      b.writeln('| ${_c(s)} | ${list.where((c) => c.status == QuestionStatus.wrong).length} | '
          '${list.where((c) => c.status == QuestionStatus.blank).length} | '
          '${top.isEmpty ? '-' : '${top.first.key.label} (${top.first.value})'} |');
    }
  }

  // ── Konu bazında ──
  final losses = topicNetLoss(mistakes, curriculum).where((t) => t.mebNodeId != null).take(15).toList();
  if (losses.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## En çok net kaybettiren konular')
      ..writeln()
      ..writeln('| Konu | Ders | Yanlış | Boş | Net kaybı |')
      ..writeln('|---|---|---|---|---|');
    for (final t in losses) {
      b.writeln('| ${_c(t.label)} | ${_c(t.sublabel)} | ${t.wrong} | ${t.blank} | ${formatNet(t.netLoss)} |');
    }
  }

  // ── Tekrarlayan hatalar ──
  final rec = recurrenceOf(mistakes, curriculum);
  final seen = <String>{};
  final recurring = <Recurrence>[];
  for (final c in mistakes) {
    final r = rec[c.id];
    if (r == null || !r.isRecurring) continue;
    final key = '${r.topic}|${r.reason?.name}';
    if (seen.add(key)) recurring.add(r);
  }
  recurring.sort((x, y) => y.score.compareTo(x.score));
  if (recurring.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Tekrarlayan hatalar')
      ..writeln();
    for (final r in recurring.take(10)) {
      b.writeln('- ${r.message}');
    }
  }

  // ── Denemeler ──
  final recentExams = [for (final e in exams) if (o.subject == null || e.section(o.subject!) != null) e]
    ..sort((x, y) => y.takenOn.compareTo(x.takenOn));
  if (recentExams.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Son denemeler')
      ..writeln()
      ..writeln('| Tarih | Deneme | Tür | Toplam net | Ders netleri |')
      ..writeln('|---|---|---|---|---|');
    for (final e in recentExams.take(5)) {
      final nets = [
        for (final s in e.sections)
          if (o.subject == null || s.subject == o.subject) '${subjectName(s.subject)} ${formatNet(s.net)}',
      ].join(', ');
      b.writeln('| ${_iso(e.takenOn)} | ${_c(e.title)} | ${e.kind.label} | ${formatNet(e.net)} | ${_c(nets)} |');
    }
  }

  // ── Kitaplar ──
  final scopedBooks = [
    for (final p in books)
      if (o.subject == null || subjectKey(p.book.examType, p.book.subject) == o.subject) p,
  ];
  if (scopedBooks.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Kitap ilerlemesi')
      ..writeln();
    for (final p in scopedBooks) {
      b.writeln('- ${p.book.title}: ${p.doneLeaves}/${p.totalLeaves} test çözüldü');
    }
  }

  // ── Son yanlışlar ──
  final shown = mistakes.take(o.maxQuestions).toList();
  final photos = <ExportMedia>[];
  if (shown.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Son yanlış ve boş sorular (en yeni ${shown.length})')
      ..writeln()
      ..writeln('| # | Tarih | Ders | Konu | Kaynak | Soru | Durum | Neden | Cevap | Not |${o.photos ? ' Dosya |' : ''}')
      ..writeln('|---|---|---|---|---|---|---|---|---|---|${o.photos ? '---|' : ''}');
    for (final (i, c) in shown.indexed) {
      final topic = topicOfCard(c, curriculum)?.label;
      String? file;
      final q = c.questionImage;
      if (o.photos && q != null) {
        final dot = q.lastIndexOf('.');
        file = 'fotograflar/${(i + 1).toString().padLeft(2, '0')}_${safeFileName(c.subject)}'
            '${dot < 0 ? '.jpg' : q.substring(dot)}';
        photos.add(ExportMedia(file, q));
      }
      b.writeln('| ${i + 1} | ${_iso(c.createdAt)} | ${_c(subjectName(c.subject))} | ${_c(topic ?? '-')} | '
          '${_c(c.testLabel ?? c.sourceName)} | ${c.questionNo ?? '-'} | ${c.status.label} | '
          '${_c(c.reasonText ?? '-')} | ${_c(c.answerText ?? '-')} | ${_c(c.note ?? '')} |'
          '${o.photos ? ' ${file ?? '-'} |' : ''}');
    }
  }
  if (scoped.isEmpty) {
    b
      ..writeln()
      ..writeln('_Bu kapsamda kayıtlı soru yok._');
  }
  return AiReport(markdown: b.toString(), photos: photos, questionCount: shown.length);
}
