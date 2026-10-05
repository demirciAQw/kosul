import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../domain/question_card.dart';
import '../../question_bank_providers.dart';
import 'media_image.dart';

Color statusColor(QuestionStatus status) => switch (status) {
      QuestionStatus.wrong => Colors.red.shade400,
      QuestionStatus.blank => Colors.orange.shade500,
      QuestionStatus.correct => Colors.green.shade500,
    };

/// Galeri hissi: soru fotoğrafı, sağ üstte yıldız (GK), altta neden + zorluk.
class QuestionTile extends ConsumerWidget {
  const QuestionTile({super.key, required this.card});
  final QuestionCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    const onImage = TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600);
    return Material(
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.push(AppRoutes.question(card.id)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaImage(card.questionImage, cacheWidth: 400),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: statusColor(card.status), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          card.reason?.label ?? card.status.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: onImage,
                        ),
                      ),
                      Text('Z${card.difficulty}', style: onImage),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: card.isStarred ? 'Güzel Sorular klasöründen çıkar' : 'Güzel Sorular klasörüne ekle',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(backgroundColor: Colors.black38),
                onPressed: () =>
                    ref.read(questionCardRepositoryProvider).setStarred(card.id, !card.isStarred),
                icon: Icon(
                  card.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: card.isStarred ? Colors.amber : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
