import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/palette.dart';
import '../../../../app/routes.dart';
import '../../../../core/text/turkish_text.dart';
import '../../domain/question_card.dart';
import '../widgets/media_image.dart';
import '../widgets/question_tile.dart' show statusColor;

/// Galeri görüntüleyici: arama/filtre sonuçlarında tam ekran sorular; sağa
/// sola kaydırarak sonuçlar arasında gezilir. Fotoğraf yakınlaştırılabilir,
/// çözüm tek dokunuşla açılır.
class QuestionViewerScreen extends StatefulWidget {
  const QuestionViewerScreen({super.key, required this.cards, required this.initialIndex});

  final List<QuestionCard> cards;
  final int initialIndex;

  static Future<void> open(BuildContext context, List<QuestionCard> cards, int index) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => QuestionViewerScreen(cards: cards, initialIndex: index),
      ));

  @override
  State<QuestionViewerScreen> createState() => _QuestionViewerScreenState();
}

class _QuestionViewerScreenState extends State<QuestionViewerScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _showSolution = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.cards[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${widget.cards.length}'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.question(card.id)),
            icon: const Icon(Icons.open_in_full_rounded, size: 18),
            label: const Text('Ayrıntı'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.cards.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _showSolution = false;
              }),
              itemBuilder: (context, i) => _Page(card: widget.cards[i], showSolution: _showSolution && i == _index),
            ),
          ),
          _InfoPanel(
            card: card,
            showSolution: _showSolution,
            onToggleSolution: card.hasSolution ? () => setState(() => _showSolution = !_showSolution) : null,
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.card, required this.showSolution});
  final QuestionCard card;
  final bool showSolution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = showSolution ? card.solutionImage : card.questionImage;
    if (showSolution && path == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(card.solutionText ?? card.answerText ?? '', style: theme.textTheme.titleMedium),
        ),
      );
    }
    if (path == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              card.questionNo == null ? '?' : '${card.questionNo}',
              style: theme.textTheme.displayLarge?.copyWith(color: statusColor(card.status)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(card.locationText, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 4),
            Text('Fotoğrafı yok', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }
    return InteractiveViewer(
      maxScale: 5,
      child: Center(child: MediaImage(path, fit: BoxFit.contain, cacheWidth: 1440)),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.card, required this.showSolution, required this.onToggleSolution});
  final QuestionCard card;
  final bool showSolution;
  final VoidCallback? onToggleSolution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = statusColor(card.status);
    final facts = [
      card.subject,
      if (card.topicText != null) titleCaseTr(card.topicText!),
      if (card.reasonText != null) card.reasonText!,
      if (card.answerText != null) card.answerText!,
    ];
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                    child: Text(card.status.label,
                        style: theme.textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  if (card.isStarred) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded, size: 20, color: KocumColors.star),
                  ],
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(card.locationText,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(facts.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              if (onToggleSolution != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: onToggleSolution,
                    icon: Icon(showSolution ? Icons.visibility_off_outlined : Icons.lightbulb_outline_rounded),
                    label: Text(showSolution ? 'Soruya dön' : 'Çözümü göster'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
