import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/export/zip_writer.dart';
import '../../curriculum/curriculum_providers.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../library/domain/progress.dart';
import '../../library/library_providers.dart';
import '../../mock_exam/domain/mock_exam.dart';
import '../../mock_exam/mock_exam_providers.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/question_bank_providers.dart';
import '../../settings/settings_providers.dart';
import '../dashboard_providers.dart';
import '../domain/ai_report.dart';

/// "Yapay zekâ raporu": istatistikleri ve yanlışları bir yapay zekâ sohbetine
/// (Claude, ChatGPT…) yapıştırılacak metne çevirir. API anahtarı gerekmez.
Future<void> showAiReportSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AiReportSheet(),
    );

class _AiReportSheet extends ConsumerStatefulWidget {
  const _AiReportSheet();

  @override
  ConsumerState<_AiReportSheet> createState() => _AiReportSheetState();
}

class _AiReportSheetState extends ConsumerState<_AiReportSheet> {
  var _o = const AiReportOptions();
  bool _busy = false;

  AiReport _build() => buildAiReport(
        cards: ref.read(allQuestionsProvider).value ?? const <QuestionCard>[],
        curriculum: {for (final n in ref.read(curriculumProvider).value ?? const <CurriculumNode>[]) n.id: n},
        exams: ref.read(mockExamsProvider).value ?? const <MockExam>[],
        books: ref.read(bookProgressProvider).value ?? const <BookProgress>[],
        now: ref.read(clockProvider)(),
        options: _o,
        findings: ref.read(deepAnalysisProvider).value?.findings ?? const [],
        fixedSchedule: ref.read(settingsProvider).value?.fixedSchedule ?? '',
        results: ref.read(testResultsProvider).value ?? const {},
      );

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final report = _build();
    await Clipboard.setData(ClipboardData(text: report.markdown));
    navigator.pop();
    messenger.showSnackBar(const SnackBar(
      content: Text('Rapor kopyalandı. Yapay zekâ sohbetine yapıştır.'),
    ));
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final media = ref.read(mediaStorageProvider);
    setState(() => _busy = true);
    try {
      final report = _build();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${now.year}-${two(now.month)}-${two(now.day)}';
      final dir = await getTemporaryDirectory();
      final File out;
      if (_o.photos && report.photos.isNotEmpty) {
        final zip = ZipWriter()..addText('rapor.md', report.markdown);
        for (final p in report.photos) {
          final f = media.resolve(p.mediaPath);
          if (await f.exists()) zip.add(p.zipName, await f.readAsBytes());
        }
        out = File('${dir.path}/Kocum_Rapor_$stamp.zip');
        await out.writeAsBytes(zip.finish(), flush: true);
      } else {
        out = File('${dir.path}/Kocum_Rapor_$stamp.md');
        await out.writeAsString(report.markdown, flush: true);
      }
      navigator.pop();
      await SharePlus.instance.share(ShareParams(
        files: [XFile(out.path)],
        subject: 'Koçum öğrenci raporu',
      ));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Rapor hazırlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = ref.watch(allQuestionsProvider).value ?? const <QuestionCard>[];
    final subjects = {for (final c in cards) c.subject}.toList()..sort();
    final preview = _build();
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text('Yapay zekâ raporu', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'İstatistiklerin ve yanlışların, ne yapılacağını anlatan bir yönergeyle birlikte tek metin olur. '
          'Kopyalayıp Claude ya da ChatGPT sohbetine yapıştır; eksiklerini ve planını sor.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text('Zaman', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final d in const [7, 30, null])
              ChoiceChip(
                label: Text(d == null ? 'Tümü' : 'Son $d gün'),
                selected: _o.days == d,
                onSelected: (_) => setState(() => _o = _o.copyWith(days: () => d)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Ders', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownMenu<String?>(
          initialSelection: _o.subject,
          expandedInsets: EdgeInsets.zero,
          menuHeight: 320,
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: null, label: 'Tüm dersler'),
            for (final s in subjects) DropdownMenuEntry(value: s, label: s),
          ],
          onSelected: (s) => setState(() => _o = _o.copyWith(subject: () => s)),
        ),
        const SizedBox(height: 12),
        Text('Listelenecek soru sayısı', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final n in const [20, 40, 80])
              ChoiceChip(
                label: Text('En yeni $n'),
                selected: _o.maxQuestions == n,
                onSelected: (_) => setState(() => _o = _o.copyWith(maxQuestions: n)),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _o.planRequest,
          onChanged: (v) => setState(() => _o = _o.copyWith(planRequest: v)),
          title: const Text('Çalışma programı iste'),
          subtitle: const Text('Yapay zekâ, Plan › İçe aktar ile eklenebilen bir program (JSON) verir'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _o.photos,
          onChanged: (v) => setState(() => _o = _o.copyWith(photos: v)),
          title: const Text('Soru fotoğraflarını da ekle'),
          subtitle: const Text('ZIP olarak paylaşılır; fotoğraf yükleyebilen sohbetlerde işe yarar'),
        ),
        const SizedBox(height: 4),
        Text(
          '${preview.questionCount} soru, yaklaşık ${(preview.markdown.length / 1000).toStringAsFixed(1)} bin karakter',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _copy,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Metni kopyala'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share_rounded),
                label: const Text('Paylaş'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
