import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/text/turkish_text.dart';
import '../../../../core/utils/formatters.dart';
import '../../../curriculum/curriculum_providers.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../domain/question_card.dart';
import '../../question_bank_providers.dart';
import '../widgets/media_image.dart';
import '../../../../app/palette.dart';
import '../../../settings/settings_providers.dart';
import '../../../ocr/ocr_providers.dart';
import '../../../ocr/domain/ocr.dart';
import '../../../../app/widgets/tone_icon.dart';

class QuestionDetailScreen extends ConsumerStatefulWidget {
  const QuestionDetailScreen({super.key, required this.cardId});
  final String cardId;

  @override
  ConsumerState<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen> {
  bool _showSolution = false;

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(questionByIdProvider(widget.cardId));
    return card.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('Soru okunamadı: $e'))),
      data: (c) => c == null
          ? Scaffold(appBar: AppBar(), body: const Center(child: Text('Soru bulunamadı.')))
          : _content(context, c),
    );
  }

  Widget _content(BuildContext context, QuestionCard card) {
    final theme = Theme.of(context);
    final curriculum = ref.watch(curriculumProvider).value ?? const <CurriculumNode>[];
    final topic = curriculum.where((n) => n.id == card.mebNodeId).firstOrNull;

    Widget meta(String text) => Chip(label: Text(text), visualDensity: VisualDensity.compact);

    return Scaffold(
      appBar: AppBar(
        title: Text(card.status.label),
        actions: [
          IconButton(
            tooltip: card.isStarred ? 'Güzel Sorular klasöründen çıkar' : 'Güzel Sorular klasörüne ekle',
            onPressed: () => ref.read(questionCardRepositoryProvider).setStarred(card.id, !card.isStarred),
            icon: Icon(
              card.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
              color: card.isStarred ? KocumColors.star : null,
            ),
          ),
          IconButton(
            tooltip: 'Düzenle',
            onPressed: () => context.push(AppRoutes.editQuestion(card.id)),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (_) => _confirmDelete(card),
            itemBuilder: (context) => const [PopupMenuItem(value: 'delete', child: Text('Soruyu sil'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (card.questionImage != null)
            GestureDetector(
              onTap: () => openImageZoom(context, card.questionImage!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MediaImage(card.questionImage!, fit: BoxFit.fitWidth, cacheWidth: 1440),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.image_not_supported_outlined),
                title: Text(card.locationText),
                subtitle: const Text('Fotoğrafı yok. Eklemek için dokun.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.editQuestion(card.id)),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              meta(card.subject),
              if (topic != null) meta(topic.title),
              meta(card.sourceName),
              if (card.testLabel != null) meta(card.testLabel!),
              if (card.questionNo != null) meta('${card.questionNo}. soru'),
              if (card.topicText != null) meta(titleCaseTr(card.topicText!)),
              if (card.reasonText != null) meta(card.reasonText!),
              if (card.answerText != null) meta(card.answerText!),
              meta('Zorluk ${card.difficulty}/10'),
              if (card.avgSecondsPerQuestion != null) meta('${card.avgSecondsPerQuestion!.round()} sn/soru'),
              meta(formatShortDate(card.createdAt)),
            ],
          ),
          const SizedBox(height: 16),
          if (!card.hasSolution)
            OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.editQuestion(card.id)),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Çözüm ekle'),
            )
          else if (!_showSolution)
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _showSolution = true),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Çözümü göster'),
            )
          else ...[
            Row(
              children: [
                Expanded(child: Text('Doğru çözüm', style: theme.textTheme.titleMedium)),
                TextButton(onPressed: () => setState(() => _showSolution = false), child: const Text('Gizle')),
              ],
            ),
            if (card.solutionImage != null)
              GestureDetector(
                onTap: () => openImageZoom(context, card.solutionImage!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MediaImage(card.solutionImage!, fit: BoxFit.fitWidth, cacheWidth: 1440),
                ),
              ),
            if (card.solutionText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(card.solutionText!, style: theme.textTheme.bodyLarge),
              ),
          ],
          if (card.questionImage != null) ...[
            const SizedBox(height: 24),
            _OcrSection(card: card),
          ],
          if (card.note != null) ...[
            const SizedBox(height: 20),
            Text('Not', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(card.note!),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(QuestionCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Soruyu sil?'),
        content: const Text('Soru, çözümü ve fotoğrafları kalıcı olarak silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final router = GoRouter.of(context);
    await ref.read(deleteQuestionCardProvider).call(card.id);
    if (router.canPop()) router.pop();
  }
}

/// Fotoğraftaki metin: arka planda okunan kök ve şıklar; doğru şık ve senin
/// şıkkın işaretli. Sırada / okunamadı durumları ve "Yeniden oku".
class _OcrSection extends ConsumerWidget {
  const _OcrSection({required this.card});
  final QuestionCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = ref.watch(settingsProvider).value?.ocrEnabled ?? true;
    final record = ref.watch(ocrRecordsProvider).value?[OcrJob.questionId(card.id)];
    final current = record != null && record.imagePath == card.questionImage ? record : null;
    final job = OcrJob(
      id: OcrJob.questionId(card.id),
      ownerType: 'question',
      ownerId: card.id,
      imagePath: card.questionImage!,
    );
    Widget retry() => TextButton.icon(
          onPressed: () => ref.read(ocrQueueProvider).retry(job),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yeniden oku'),
        );
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final Widget body;
    if (current == null) {
      body = Text(
        enabled
            ? 'Sırada: fotoğraftaki metin arka planda okunacak.'
            : 'Kapalı: Ayarlar › Fotoğraftaki metin ile açabilirsin.',
        style: muted,
      );
    } else if (!current.ok) {
      body = Text('Okunamadı${current.error == null ? '' : ': ${current.error}'}', style: muted);
    } else if (current.fullText.trim().isEmpty) {
      body = Text('Fotoğrafta okunabilir metin bulunamadı.', style: muted);
    } else {
      final p = current.parsed;
      final options = p?.options ?? const <String, String>{};
      // Şekil, grafik, tablo, fotoğraf (el yazısı işaretleri hariç), birer kez.
      final figures = {
        for (final f in current.figures)
          if (f['kind'] != 'annotation')
            switch (f['kind']) { 'photo' => 'Fotoğraf', 'table' => 'Tablo', 'chart' => 'Grafik', _ => 'Şekil' },
      }.toList();
      final questionCount = (current.structure?['questions'] as List?)?.length ?? 1;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p?.number != null) Text('Soru ${p!.number}', style: theme.textTheme.labelLarge),
          SelectableText(
            (p != null && p.stem.isNotEmpty) ? p.stem : current.fullText,
            style: theme.textTheme.bodyMedium,
          ),
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.key == card.correctAnswer
                          ? KocumColors.correct
                          : (e.key == card.givenAnswer ? KocumColors.wrong : scheme.surfaceContainerHighest),
                    ),
                    child: Text(
                      e.key,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: (e.key == card.correctAnswer || e.key == card.givenAnswer) ? Colors.white : null,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(e.value, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          if (figures.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in figures)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(_figureIcon(f), size: 16),
                    label: Text(f),
                  ),
              ],
            ),
          ],
          if (questionCount > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Fotoğrafta $questionCount soru bulundu; asıl soru gösteriliyor.', style: muted),
            ),
          const SizedBox(height: 6),
          Text(
            'Telefonda otomatik okundu${current.durationMs == null ? '' : ' (${current.durationMs} ms)'}. '
            'Formüllerde ve el yazısında hata olabilir.',
            style: muted,
          ),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ToneIcon(Icons.document_scanner_outlined, color: KocumColors.green, size: 32),
                const SizedBox(width: 10),
                Expanded(child: Text('Fotoğraftaki metin', style: theme.textTheme.titleSmall)),
                if (enabled && (current == null || !current.ok || current.fullText.trim().isEmpty)) retry(),
                if (current != null && current.ok && current.fullText.trim().isNotEmpty) retry(),
              ],
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

IconData _figureIcon(String label) => switch (label) {
      'Fotoğraf' => Icons.photo_outlined,
      'Tablo' => Icons.table_chart_outlined,
      'Grafik' => Icons.show_chart_rounded,
      _ => Icons.category_outlined,
    };
