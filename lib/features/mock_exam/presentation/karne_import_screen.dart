import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/text/turkish_text.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/domain/yks.dart';
import '../../question_bank/presentation/widgets/question_tile.dart' show statusColor;
import '../data/karne_pdf_reader.dart';
import '../domain/karne_import.dart';
import '../domain/karne_parser.dart';
import '../domain/mock_exam.dart';
import '../mock_exam_providers.dart';

/// Karne PDF'lerini seç → oku → (tek dosyada önizleme) → kaydet.
/// Birden çok dosya seçilirse önizlemesiz, sırayla eklenir; aynı deneme
/// zaten varsa o dosya atlanır.
Future<void> importKarneFlow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final List<KarneFile> files;
  try {
    files = await pickKarneFiles();
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Dosya açılamadı: $e')));
    return;
  }
  if (files.isEmpty || !context.mounted) return;

  final plans = <(String, KarneImportPlan)>[];
  final errors = <String>[];
  for (final f in files) {
    try {
      final words = await readKarneWords(f.bytes);
      plans.add((f.name, planKarneImport(parseKarne(words))));
    } on KarneFormatException catch (e) {
      errors.add('${f.name}: ${e.message}');
    } catch (e) {
      errors.add('${f.name}: okunamadı ($e)');
    }
  }
  if (!context.mounted) return;
  if (errors.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(plans.isEmpty ? 'Karne okunamadı' : 'Bazı dosyalar okunamadı'),
        content: Text(errors.join('\n\n')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Tamam'))],
      ),
    );
  }
  if (plans.isEmpty || !context.mounted) return;

  if (plans.length == 1) {
    await router.push(AppRoutes.karneImport, extra: plans.single.$2);
    return;
  }

  // Çoklu: önizlemesiz ekle.
  final importer = ref.read(importKarneProvider);
  var added = 0, cards = 0;
  final skipped = <String>[];
  for (final (_, plan) in plans) {
    try {
      final r = await importer.call(plan);
      added++;
      cards += r.cards;
    } on KarneDuplicateException catch (e) {
      skipped.add(e.existing.title);
    }
  }
  messenger.showSnackBar(SnackBar(
    content: Text([
      '$added deneme eklendi, $cards soru deftere düştü.',
      if (skipped.isNotEmpty) '${skipped.length} deneme zaten kayıtlıydı, atlandı.',
    ].join(' ')),
  ));
}

/// Tek karnenin önizlemesi: kaydetmeden önce neyin ekleneceği görünür.
class KarneImportScreen extends ConsumerStatefulWidget {
  const KarneImportScreen({super.key, required this.plan});
  final KarneImportPlan plan;

  @override
  ConsumerState<KarneImportScreen> createState() => _KarneImportScreenState();
}

class _KarneImportScreenState extends ConsumerState<KarneImportScreen> {
  late final _title = TextEditingController(text: widget.plan.data.title);
  bool _addMistakes = true;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save({bool replace = false}) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final r = await ref.read(importKarneProvider).call(
            widget.plan,
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            addMistakes: _addMistakes,
            replace: replace,
          );
      ref.read(mockKindFilterProvider.notifier).set(r.exam.kind);
      messenger.showSnackBar(SnackBar(
        content: Text('${r.exam.title} eklendi: ${formatNet(r.exam.net)} net'
            '${r.cards > 0 ? ', ${r.cards} soru deftere düştü' : ''}.'),
      ));
      router.pushReplacement(AppRoutes.mockExam(r.exam.id));
    } on KarneDuplicateException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Bu deneme zaten kayıtlı'),
          content: Text(
            '${e.existing.title} (${formatDate(e.existing.takenOn)}) daha önce eklenmiş. '
            'Yenisiyle değiştirilsin mi? Eskisinin fotoğraf eklemediğin soruları da silinir.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Değiştir')),
          ],
        ),
      );
      if (ok == true && mounted) await _save(replace: true);
    } on MockExamException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plan = widget.plan;
    final d = plan.data;
    final total = plan.sections.fold<int>(0, (a, s) => a + s.questionCount);
    final c = plan.sections.fold<int>(0, (a, s) => a + s.correct);
    final w = plan.sections.fold<int>(0, (a, s) => a + s.wrong);
    final b = plan.sections.fold<int>(0, (a, s) => a + s.blank);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Karneden deneme'),
        leading: IconButton(
          tooltip: 'Vazgeç',
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Deneme adı'),
          ),
          const SizedBox(height: 8),
          Text(
            [
              plan.kind.label,
              if (d.date != null) formatDate(d.date!),
              if (d.booklet != null) '${d.booklet} kitapçığı',
            ].join(', '),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatNet(plan.net), style: theme.textTheme.displaySmall?.copyWith(color: scheme.primary)),
                      Text('net, $total soru', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      [
                        '$c doğru, $w yanlış, $b boş',
                        if (d.score != null) '${plan.kind.label} puanı ${d.score!.replaceAll('.', ',')}',
                        if (d.ranks.isNotEmpty) 'Sınıf sırası ${d.ranks.first.$1}/${d.ranks.first.$2}',
                      ].join('\n'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Dersler', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final s in plan.sections)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text(subjectName(s.subject), style: theme.textTheme.bodyLarge)),
                  Text('${s.correct} D  ${s.wrong} Y  ${s.blank} B', style: theme.textTheme.bodyMedium),
                  SizedBox(
                    width: 64,
                    child: Text(
                      formatNet(netOf(s.correct, s.wrong)),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          if (plan.skipped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${plan.skipped.join(', ')} girilmemiş; denemeye eklenmeyecek.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              value: _addMistakes,
              onChanged: (v) => setState(() => _addMistakes = v),
              title: Text('${plan.wrongCount} yanlış ve ${plan.blankCount} boşu deftere ekle'),
              subtitle: const Text(
                'Kazanımı, kitapçık numarası, doğru cevap ve senin cevabınla eklenir. '
                'Fotoğrafını sonra Eksikler\'den ekleyebilirsin.',
              ),
            ),
          ),
          if (_addMistakes && plan.mistakes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final m in plan.mistakes.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: statusColor(m.status),
                  child: Text('${m.questionNo}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
                title: Text(titleCaseTr(m.kazanim)),
                subtitle: Text([subjectName(m.subject), if (m.answerNote != null) m.answerNote!].join(', ')),
              ),
            if (plan.mistakes.length > 8)
              Text(
                've ${plan.mistakes.length - 8} soru daha',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Vazgeç'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Kaydet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
