import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/mock_exam.dart';

/// "En çok net kaybettiren konular": her yanlış 1,25, her boş 1 net.
class TopicLossList extends StatelessWidget {
  const TopicLossList({super.key, required this.losses, this.limit = 8});

  final List<TopicLoss> losses;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (losses.isEmpty) {
      return Text(
        'Optik formla yanlışlarını işaretleyip konularını girdikçe burada hangi konunun kaç net kaybettirdiği görünür.',
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    final tagged = [for (final l in losses) if (l.mebNodeId != null) l];
    final untagged = losses.where((l) => l.mebNodeId == null).firstOrNull;
    final maxLoss = tagged.isEmpty ? 1.0 : tagged.first.netLoss;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in tagged.take(limit))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    ),
                    const SizedBox(width: 8),
                    Text('${formatNet(l.netLoss)} net', style: theme.textTheme.labelLarge?.copyWith(color: scheme.error)),
                  ],
                ),
                Text(
                  [
                    if (l.sublabel != null) l.sublabel!,
                    if (l.wrong > 0) '${l.wrong} yanlış',
                    if (l.blank > 0) '${l.blank} boş',
                  ].join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: maxLoss == 0 ? 0 : l.netLoss / maxLoss,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  color: scheme.error,
                  backgroundColor: scheme.errorContainer.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        if (untagged != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${untagged.wrong + untagged.blank} sorunun konusu girilmemiş '
                    '(${formatNet(untagged.netLoss)} net).',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(AppRoutes.incompleteQuestions),
                  child: const Text('Eksiklere git'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
