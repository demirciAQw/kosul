import '../../../core/export/zip_writer.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../curriculum/domain/yks.dart';
import '../../library/domain/library.dart';
import '../../library/domain/progress.dart';
import '../../planning/domain/plan_import.dart' show planJsonSchema;
import '../../mock_exam/domain/mock_exam.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/domain/question_export.dart' show ExportMedia;
import '../../question_bank/domain/recurrence.dart';
import '../../study_session/domain/study_session.dart';
import 'deep_analysis.dart';
import 'stem_analysis.dart';

/// Yapay zekâ raporunun kapsamı.
class AiReportOptions {
  const AiReportOptions({
    this.days = 30,
    this.subject,
    this.maxQuestions = 40,
    this.photos = false,
    this.planRequest = true,
    this.since,
    this.label,
  });

  /// Son kaç günün soruları (null = hepsi).
  final int? days;

  /// Tek bir ders (null = tüm dersler).
  final String? subject;
  final int maxQuestions;

  /// Soru fotoğrafları da pakete girsin (ZIP).
  final bool photos;

  /// Yapay zekâdan uygulamaya aktarılabilir bir çalışma programı (JSON) iste.
  final bool planRequest;

  /// Verilirse [days] yerine bu andan sonraki kayıtlar (Claude "yeni veriler" paketi).
  final DateTime? since;

  /// Paket etiketi, ör. "Paket #4".
  final String? label;

  AiReportOptions copyWith({
    int? Function()? days,
    String? Function()? subject,
    int? maxQuestions,
    bool? photos,
    bool? planRequest,
  }) =>
      AiReportOptions(
        days: days != null ? days() : this.days,
        subject: subject != null ? subject() : this.subject,
        maxQuestions: maxQuestions ?? this.maxQuestions,
        photos: photos ?? this.photos,
        planRequest: planRequest ?? this.planRequest,
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
  List<Finding> findings = const [],
  String fixedSchedule = '',
  Map<String, TestResult> results = const {},
  List<StudySession> sessions = const [],
  DateTime? deadline,
  /// Kart → fotoğraftan okunan soru metni (kök ve şıklar).
  Map<String, String> questionTexts = const {},
  /// Soru kökü analizi (olumsuz, öncüllü, "en …" kökler; tekrar eden kalıplar).
  StemReport? stems,
}) {
  final o = options;
  final since = o.since ?? (o.days == null ? null : now.subtract(Duration(days: o.days!)));
  final everything = o.since == null && o.days == null;
  bool inScope(QuestionCard c) =>
      (o.subject == null || c.subject == o.subject) && (since == null || !c.createdAt.isBefore(since));
  final scoped = [for (final c in cards) if (inScope(c)) c];
  final mistakes = [for (final c in scoped) if (c.status != QuestionStatus.correct) c]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final wrong = scoped.where((c) => c.status == QuestionStatus.wrong).length;
  final blank = scoped.where((c) => c.status == QuestionStatus.blank).length;
  final correct = scoped.length - wrong - blank;

  final b = StringBuffer()
    ..writeln('# Koçum öğrenci raporu (${_iso(now)})${o.label == null ? '' : ' — ${o.label}'}')
    ..writeln()
    ..writeln('## Senden istediğim')
    ..writeln()
    ..writeln('Sen deneyimli bir YKS koçusun. Aşağıdaki veriler YKS\'ye hazırlanan bir öğrencinin '
        'çalışma uygulamasından alındı. Lütfen:')
    ..writeln('1. En çok net kaybettiren eksik konuları, nedenleriyle birlikte önem sırasına koy (en fazla 5).')
    ..writeln('2. Tekrarlayan hata örüntülerini açıkla: aynı konu, aynı neden, aynı tür soru.')
    ..writeln('3. Her eksik için somut bir çalışma önerisi ver: hangi konuya dön, kaç soru çöz, hangi sırayla.')
    ..writeln('4. Eksikler için MEB kitaplarından nokta atışı yer öner: kitap, bölüm ve sayfa (yalnızca aşağıdaki '
        'içindekilerde olanlar).')
    ..writeln('5. Derin analiz bulgularına bakarak hangi saatlerde ve hangi hızda daha verimli olduğumu, hangi '
        'kaynağın bana zor geldiğini yorumla.')
    ..writeln('6. Bir haftalık kısa ve gerçekçi bir plan öner (günde en fazla 2-3 saat), sabit programımın dışına.')
    ..writeln()
    ..writeln('Sohbette günlük notlarımı (uyku, yorgunluk, o günkü durum) yazabilirim; tarihleri eşleştirerek '
        'o günlerdeki sonuçlarla karşılaştır.')
    ..writeln()
    ..writeln('"Soru metni" sütunu fotoğraftan telefonda otomatik okundu; formüller ve el yazısı bozuk '
        'olabilir. Doğru cevap ve öğrencinin cevabıyla karşılaştırarak hatanın nerede olduğunu yorumla.')
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
    ..writeln('- Kapsam: ${o.since != null ? '${_iso(o.since!)} ${_two(o.since!.hour)}:${_two(o.since!.minute)} sonrasındaki yeni veriler' : (o.days == null ? 'tüm zamanlar' : 'son ${o.days} gün')}, ${o.subject ?? 'tüm dersler'}')
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
  final recentExams = [
    for (final e in exams)
      if ((o.subject == null || e.section(o.subject!) != null) && (o.since == null || !e.createdAt.isBefore(o.since!))) e,
  ]..sort((x, y) => y.takenOn.compareTo(x.takenOn));
  final examLimit = everything ? 60 : 5;
  if (recentExams.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Son denemeler')
      ..writeln()
      ..writeln('| Tarih | Deneme | Tür | Toplam net | Ders netleri |')
      ..writeln('|---|---|---|---|---|');
    for (final e in recentExams.take(examLimit)) {
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

  // ── Çalışma oturumları ──
  final scopedSessions = [
    for (final s in sessions)
      if (since == null || !s.startedAt.isBefore(since)) s,
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  if (scopedSessions.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Çalışma oturumları (${scopedSessions.length})')
      ..writeln()
      ..writeln('| Tarih | Başlangıç | Süre (dk) | Blok | Ders | D | Y | B |')
      ..writeln('|---|---|---|---|---|---|---|---|');
    var rows = 0;
    for (final s in scopedSessions) {
      final minutes = s.endedAt == null ? '-' : '${s.endedAt!.difference(s.startedAt).inMinutes}';
      for (final i in s.items) {
        if (o.subject != null && i.subject != o.subject) continue;
        if (rows++ >= 400) break;
        b.writeln('| ${_iso(s.startedAt)} | ${_two(s.startedAt.hour)}:${_two(s.startedAt.minute)} | $minutes | '
            '${_c(i.label)} | ${_c(i.subject == null ? '-' : subjectName(i.subject!))} | '
            '${i.correct ?? '-'} | ${i.wrong ?? '-'} | ${i.blank ?? '-'} |');
      }
    }
  }

  // ── Hedef: tüm kitapları bitirmek ──
  if (deadline != null) {
    final own = [for (final p in books) if ((p.book.publisher ?? '').trim().toUpperCase() != 'MEB') p];
    final total = own.fold<int>(0, (a, p) => a + p.totalLeaves);
    final done = own.fold<int>(0, (a, p) => a + p.doneLeaves);
    final left = total - done;
    final today = DateTime(now.year, now.month, now.day);
    final daysLeft = DateTime(deadline.year, deadline.month, deadline.day).difference(today).inDays;
    final recent = results.values.where((r) => now.difference(r.solvedAt).inDays < 14).length;
    final pace = recent / 14;
    b
      ..writeln()
      ..writeln('## Hedef: tüm kitapları ${_iso(deadline)} tarihine kadar bitirmek')
      ..writeln()
      ..writeln('- Kitaplarda $total testten $done tanesi bitti, $left kaldı.')
      ..writeln('- Kalan gün: $daysLeft${daysLeft > 0 ? ' (günde ${(left / daysLeft).toStringAsFixed(1)} test gerekiyor)' : ''}')
      ..writeln('- Son 14 günün hızı: günde ${pace.toStringAsFixed(1)} test.'
          '${pace > 0 && left > 0 ? ' Bu hızla ${_iso(today.add(Duration(days: (left / pace).ceil())))} tarihinde biter.' : ''}');
    for (final p in own) {
      b.writeln('- ${p.book.title}: ${p.doneLeaves}/${p.totalLeaves}');
    }
  }

  // ── Soru kökleri ──
  if (stems != null && stems.mistakes > 0) {
    b
      ..writeln()
      ..writeln('## Soru kökleri (fotoğraftan okunan ${stems.mistakes} yanlış/boş soru)')
      ..writeln()
      ..writeln('- Sonuç: ${stems.verdict}')
      ..writeln('- Dağılım: ${[for (final e in stems.counts.entries) if (e.value > 0) '${e.key.label} ${e.value}'].join(', ')}');
    for (final t in stems.trends.skip(1)) {
      b.writeln('- ${t.text}');
    }
    for (final t in stems.templates) {
      b.writeln('- Tekrar eden kalıp "${_c(t.example)}": ${t.count} kez (${t.wrong} yanlış, ${t.blank} boş, '
          '${t.careless} dikkatsizlik)');
    }
    b.writeln('- Not: Defterde çoğunlukla yanlışlar olduğundan oranlar yanlışların içindeki paylardır.');
  }

  // ── Derin analiz ──
  if (findings.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Derin analiz bulguları (uygulama hesapladı)')
      ..writeln()
      ..writeln('Yalnızca aynı koşullarda (aynı ders, kaynak vb.) tekrar tekrar görülen ve istatistiksel olarak '
          'güvenilir farklar listelenir.')
      ..writeln();
    for (final f in findings) {
      b.writeln('- ${f.factor.title}: ${f.sentence} (${f.evidence})');
    }
  }

  // ── Sabit program ──
  if (fixedSchedule.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Haftalık sabit programım (okul, kurs, dershane)')
      ..writeln()
      ..writeln(fixedSchedule.trim());
  }

  // ── Kaynaklar: kalan testler ve MEB içindekiler ──
  final ownBooks = [for (final p in scopedBooks) if ((p.book.publisher ?? '').trim().toUpperCase() != 'MEB') p.book];
  final mebBooks = [for (final p in scopedBooks) if ((p.book.publisher ?? '').trim().toUpperCase() == 'MEB') p.book];
  if (ownBooks.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Kaynaklarımda kalan testler')
      ..writeln();
    for (final book in ownBooks) {
      b.writeln('### ${book.title}');
      var lines = 0;
      for (final unit in book.roots) {
        for (final konu in unit.children.isEmpty ? [unit] : unit.children) {
          final leaves = leavesUnder(konu);
          final left = leaves.where((l) => !results.containsKey(l.id)).length;
          if (left == 0 || lines >= 40) continue;
          b.writeln('- ${unit.title} › ${konu.title}: ${leaves.length} testten $left kaldı');
          lines++;
        }
      }
    }
  }
  if (mebBooks.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## MEB kitaplarının içindekileri (sayfalarıyla)')
      ..writeln();
    for (final book in mebBooks) {
      b.writeln('### ${book.title}');
      for (final unit in book.roots) {
        b.writeln('- ${unit.title}${_pages(unit)}');
        for (final konu in unit.children) {
          b.writeln('  - ${konu.title}${_pages(konu)}');
        }
      }
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
      ..writeln('| # | Tarih | Ders | Konu | Kaynak | Soru | Durum | Neden | Cevap | Not | Soru metni (fotoğraftan) |'
          '${o.photos ? ' Dosya |' : ''}')
      ..writeln('|---|---|---|---|---|---|---|---|---|---|---|${o.photos ? '---|' : ''}');
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
          '${_c(c.reasonText ?? '-')} | ${_c(c.answerText ?? '-')} | ${_c(c.note ?? '')} | '
          '${_c(_clip(questionTexts[c.id]))} |'
          '${o.photos ? ' ${file ?? '-'} |' : ''}');
    }
  }
  if (o.planRequest) {
    b
      ..writeln()
      ..writeln('## Çalışma programı biçimi')
      ..writeln()
      ..writeln('Programı, uygulamama aktarabilmem için en sonda tek bir ```json bloğu olarak ver. Biçim:')
      ..writeln()
      ..writeln('```json')
      ..writeln(planJsonSchema)
      ..writeln('```')
      ..writeln()
      ..writeln('Kurallar: kitap ve bölüm adlarını yukarıdaki listelerde yazdığı gibi kullan; sabit programımın '
          'saatlerine görev koyma; günde en fazla 2-3 saat; her görev en fazla 60 dakika; tarihleri '
          '${_iso(now)} sonrasından başlat.');
  }
  if (scoped.isEmpty) {
    b
      ..writeln()
      ..writeln('_Bu kapsamda kayıtlı soru yok._');
  }
  return AiReport(markdown: b.toString(), photos: photos, questionCount: shown.length);
}

String _pages(ContentNode n) {
  final a = n.pageStart, z = n.pageEnd;
  if (a == null) return '';
  return z == null || z == a ? ' (s. $a)' : ' (s. $a–$z)';
}

/// Tablo hücresi için kısaltılmış metin (yoksa "-").
String _clip(String? s, {int max = 320}) {
  if (s == null || s.trim().isEmpty) return '-';
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > max ? '${t.substring(0, max)}…' : t;
}
