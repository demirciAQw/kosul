import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/palette.dart';
import '../../../app/routes.dart';
import '../../../app/widgets/tone_icon.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/curriculum_providers.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../dashboard/dashboard_providers.dart';
import '../../dashboard/domain/ai_report.dart';
import '../../dashboard/presentation/ai_report_sheet.dart';
import '../../library/domain/library.dart';
import '../../library/domain/progress.dart';
import '../../library/library_providers.dart';
import '../../mock_exam/domain/mock_exam.dart';
import '../../mock_exam/mock_exam_providers.dart';
import '../../notes/domain/notes.dart';
import '../../notes/notes_providers.dart';
import '../../planning/domain/planning.dart';
import '../../planning/planning_providers.dart';
import '../../question_bank/question_bank_providers.dart';
import '../../settings/settings_providers.dart';
import '../../study_session/study_session_providers.dart';
import '../data/full_export.dart';
import '../domain/export_log.dart';
import '../tools_providers.dart';
import '../../../core/export/xlsx_writer.dart';
import '../data/workbook_export.dart';
import '../../ocr/ocr_providers.dart';
import '../../ocr/auto_tag_providers.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _stamp(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}_${_two(d.hour)}${_two(d.minute)}';

/// Araçlar: hedef, Claude paketleri, dışa aktarma, test oluşturma, görünüm.
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  bool _busy = false;

  Future<File> _temp(String name) async => File('${(await getTemporaryDirectory()).path}/$name');

  /// Claude paketi: [full] ise tüm veri, değilse son paketten bu yana. Görselsiz.
  Future<void> _sendClaude({required bool full}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final logRepo = ref.read(exportLogRepositoryProvider);
      final log = await logRepo.load();
      final since = full ? null : nextSince(log);
      final now = ref.read(clockProvider)();
      final number = log.isEmpty ? 1 : log.map((b) => b.number).reduce((a, b) => a > b ? a : b) + 1;
      final sessions = await ref.read(studySessionRepositoryProvider).watchHistory(limit: 5000).first;
      final settings = ref.read(settingsProvider).value;
      final report = buildAiReport(
        cards: await ref.read(allQuestionsProvider.future),
        curriculum: {for (final n in ref.read(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n},
        exams: ref.read(mockExamsProvider).value ?? const <MockExam>[],
        books: ref.read(bookProgressProvider).value ?? const <BookProgress>[],
        now: now,
        options: AiReportOptions(
          days: null,
          since: since,
          maxQuestions: 100000,
          label: 'Paket #$number${full ? ' (tüm veri)' : (since == null ? ' (ilk paket)' : '')}',
        ),
        findings: ref.read(deepAnalysisProvider).value?.findings ?? const [],
        fixedSchedule: settings?.fixedSchedule ?? '',
        results: ref.read(testResultsProvider).value ?? const {},
        questionTexts: ocrQuestionTextsWithFigures(ref.read(ocrRecordsProvider).value ?? const {},
            tags: ref.read(autoTagsProvider)),
        stems: ref.read(stemReportProvider),
        sessions: sessions,
        deadline: settings?.booksDeadline,
      );
      final out = await _temp('Kocum_Claude_Paket$number${full ? '_tum' : ''}_${_stamp(now)}.md');
      await out.writeAsString(report.markdown, flush: true);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(out.path, mimeType: 'text/markdown')],
        subject: 'Koçum Paket #$number',
      ));
      if (result.status == ShareResultStatus.dismissed) {
        messenger.showSnackBar(const SnackBar(content: Text('Paylaşım iptal edildi; paket kaydedilmedi.')));
        return;
      }
      final newSessions = sessions.where((s) => since == null || !s.startedAt.isBefore(since)).length;
      final batch = await logRepo.append(
        at: now,
        from: since,
        full: full,
        questions: report.questionCount,
        sessions: newSessions,
      );
      ref.invalidate(claudeExportLogProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('${batch.label} hazır: ${report.questionCount} soru, $newSessions oturum. '
            'Claude projesine yükle.'),
      ));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Paket hazırlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fullBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final now = ref.read(clockProvider)();
      final cards = await ref.read(allQuestionsProvider.future);
      final notes = ref.read(notesProvider).value ?? const <StudyNote>[];
      final data = fullDataJson(
        now: now,
        cards: cards,
        books: ref.read(libraryProvider).value ?? const <Book>[],
        results: ref.read(testResultsProvider).value ?? const {},
        sessions: await ref.read(studySessionRepositoryProvider).watchHistory(limit: 100000).first,
        exams: ref.read(mockExamsProvider).value ?? const <MockExam>[],
        plans: ref.read(plansProvider).value ?? const <StudyPlan>[],
        notes: notes,
        ocr: [for (final r in (ref.read(ocrRecordsProvider).value ?? const {}).values) r.toDatasetJson()],
      );
      // Arama veri seti (varsa) de pakete girer.
      final extra = <String, List<int>>{};
      final log = await ref.read(searchLogProvider).file();
      final ocrLog = await ref.read(ocrLogProvider).file();
      for (final f in [log, File('${log.path}.1'), ocrLog, File('${ocrLog.path}.1')]) {
        if (await f.exists()) extra['veri/${f.uri.pathSegments.last}'] = await f.readAsBytes();
      }
      final zip = await buildFullExportZip(
        data: data,
        cards: cards,
        notes: notes,
        media: ref.read(mediaStorageProvider),
        extraFiles: extra,
      );
      final out = await _temp('Kocum_Tum_Veri_${_stamp(now)}.zip');
      await out.writeAsBytes(zip.bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(out.path, mimeType: 'application/zip')],
        subject: 'Koçum tüm veri',
        text: '${cards.length} soru, ${zip.photos} fotoğraf${zip.missing > 0 ? ' (${zip.missing} bulunamadı)' : ''}',
      ));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Dışa aktarılamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tüm veri, LibreOffice Calc / Excel'de açılan çok sayfalı tablo (.xlsx).
  Future<void> _spreadsheet() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final now = ref.read(clockProvider)();
      final sheets = dataWorkbook(
        cards: await ref.read(allQuestionsProvider.future),
        curriculum: {for (final n in ref.read(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n},
        books: ref.read(libraryProvider).value ?? const <Book>[],
        progress: ref.read(bookProgressProvider).value ?? const <BookProgress>[],
        results: ref.read(testResultsProvider).value ?? const {},
        sessions: await ref.read(studySessionRepositoryProvider).watchHistory(limit: 100000).first,
        exams: ref.read(mockExamsProvider).value ?? const <MockExam>[],
        plans: ref.read(plansProvider).value ?? const <StudyPlan>[],
        notes: ref.read(notesProvider).value ?? const <StudyNote>[],
        findings: ref.read(deepAnalysisProvider).value?.findings ?? const [],
      );
      final out = await _temp(workbookFileName(now));
      await out.writeAsBytes(buildXlsx(sheets, time: now), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(out.path, mimeType: xlsxMimeType)],
        subject: 'Koçum verileri',
        text: [for (final s in sheets) '${s.name}: ${s.rows.length}'].join(', '),
      ));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Tablo hazırlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDeadline() async {
    final s = ref.read(settingsProvider).value;
    if (s == null) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: s.booksDeadline ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: DateTime(now.year + 3),
      helpText: 'Tüm kitapları bitirme tarihi',
    );
    if (picked == null) return;
    await ref.read(settingsProvider.notifier).change(s.copyWith(booksDeadline: () => picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).value;
    final log = ref.watch(claudeExportLogProvider).value ?? const <ClaudeBatch>[];
    final last = log.isEmpty ? null : log.last;
    final books = ref.watch(bookProgressProvider).value ?? const <BookProgress>[];
    final own = [for (final p in books) if ((p.book.publisher ?? '').trim().toUpperCase() != 'MEB') p];
    final left = own.fold<int>(0, (a, p) => a + p.totalLeaves - p.doneLeaves);
    final deadline = settings?.booksDeadline;
    final today = DateTime.now();
    final daysLeft = deadline == null
        ? null
        : DateTime(deadline.year, deadline.month, deadline.day).difference(DateTime(today.year, today.month, today.day)).inDays;

    Widget tile(IconData icon, Color color, String title, String subtitle, VoidCallback? onTap) => ListTile(
          leading: ToneIcon(icon, color: color),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: _busy ? null : onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Araçlar')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              const _Section('Hedef'),
              Card(
                child: tile(
                  Icons.flag_outlined,
                  KocumColors.green,
                  deadline == null ? 'Kitapları bitirme hedefi koy' : 'Hedef: ${formatDate(deadline)}',
                  deadline == null
                      ? 'Kalan $left test için günlük hızı hesaplar; Claude paketlerine de girer'
                      : (daysLeft! > 0
                          ? '$left test, $daysLeft gün: günde ${(left / daysLeft).toStringAsFixed(1)} test'
                          : 'Hedef tarihi geçti; yeni bir tarih seç'),
                  _pickDeadline,
                ),
              ),
              const _Section('Claude\'a gönder (görselsiz)'),
              Card(
                child: Column(
                  children: [
                    tile(
                      Icons.auto_awesome_outlined,
                      KocumColors.blue,
                      'Yeni verileri gönder',
                      last == null
                          ? 'İlk paket: şimdiye kadarki her şey'
                          : '${last.label} (${formatDate(last.at)}) sonrası eklenenler, etiketleriyle',
                      () => _sendClaude(full: false),
                    ),
                    const Divider(indent: 72),
                    tile(
                      Icons.all_inclusive_rounded,
                      KocumColors.blue,
                      'Tüm veriyi gönder',
                      'Bütün istatistikler, oturumlar, denemeler ve sorular',
                      () => _sendClaude(full: true),
                    ),
                    const Divider(indent: 72),
                    tile(
                      Icons.tune_rounded,
                      KocumColors.grey700,
                      'Seçenekli rapor',
                      'Zaman, ders, soru sayısı ve fotoğraf seçerek',
                      () => showAiReportSheet(context),
                    ),
                  ],
                ),
              ),
              const _Section('Dışa aktar'),
              Card(
                child: Column(
                  children: [
                    tile(
                      Icons.picture_as_pdf_outlined,
                      KocumColors.red,
                      'Yanlış defteri (PDF)',
                      'Defter\'de ara ve süz, seçtiğin sorular sayfada 4 soru olarak',
                      () {
                        ref.read(notebookPdfRequestProvider.notifier).set(true);
                        context.go(AppRoutes.notebook);
                      },
                    ),
                    const Divider(indent: 72),
                    tile(
                      Icons.quiz_outlined,
                      KocumColors.amber,
                      'Yanlışlarımdan test oluştur',
                      'Ders, konu, zorluk, neden ve soru sayısına göre PDF test',
                      () => context.push(AppRoutes.practiceTest),
                    ),
                    const Divider(indent: 72),
                    tile(
                      Icons.table_chart_outlined,
                      KocumColors.green,
                      'Tablo (LibreOffice Calc / Excel)',
                      'Sorular, oturumlar, kitap testleri, denemeler… ayrı sayfalarda; filtreli ve sıralanabilir',
                      _spreadsheet,
                    ),
                    const Divider(indent: 72),
                    tile(
                      Icons.inventory_2_outlined,
                      KocumColors.green,
                      'Tüm veriyi dışa aktar',
                      'Her şey tek ZIP: veriler (JSON) ve tüm fotoğraflar',
                      _fullBackup,
                    ),
                  ],
                ),
              ),
              const _Section('Görünüm'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('Telefon'), icon: Icon(Icons.smartphone_rounded)),
                        ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode_outlined)),
                        ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode_outlined)),
                      ],
                      selected: {settings?.themeMode ?? ThemeMode.system},
                      onSelectionChanged: settings == null
                          ? null
                          : (v) => ref.read(settingsProvider.notifier).change(settings.copyWith(themeMode: v.first)),
                    ),
                  ),
                ),
              ),
              Card(
                child: tile(
                  Icons.settings_outlined,
                  KocumColors.grey700,
                  'Ayarlar',
                  'Hatırlatıcılar ve haftalık sabit program',
                  () => context.push(AppRoutes.settings),
                ),
              ),
              if (log.isNotEmpty) ...[
                const _Section('Claude paket geçmişi'),
                Card(
                  child: Column(
                    children: [
                      for (final b in log.reversed.take(10))
                        ListTile(
                          dense: true,
                          title: Text('${b.label}${b.full ? ' · tüm veri' : ''}'),
                          subtitle: Text(
                            '${formatDate(b.at)}'
                            '${b.from == null ? '' : ' (${formatDate(b.from!)} sonrası)'}, '
                            '${b.questions} soru, ${b.sessions} oturum',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (_busy) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
