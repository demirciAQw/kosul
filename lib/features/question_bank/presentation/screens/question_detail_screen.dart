import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../../curriculum/curriculum_providers.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../domain/question_card.dart';
import '../../question_bank_providers.dart';
import '../widgets/media_image.dart';

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
              color: card.isStarred ? Colors.amber.shade600 : null,
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
              if (card.reasonText != null) meta(card.reasonText!),
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
