import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/palette.dart';
import '../../../app/widgets/tone_icon.dart';
import '../dashboard_providers.dart';
import '../domain/stem_analysis.dart';

/// Analiz › Soru kökleri: olumsuz, öncüllü, "en …" köklerde açık ara bir
/// eğilim var mı; tekrar eden soru kalıpları.
class StemAnalysisSection extends ConsumerWidget {
  const StemAnalysisSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(stemReportProvider);
    if (report == null || report.analyzed == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final total = report.counts.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ToneIcon(Icons.text_snippet_outlined, color: KocumColors.blue),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Soru kökleri', style: theme.textTheme.titleMedium)),
                  Text('${report.mistakes} yanlış/boş', style: muted),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                report.verdict,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: report.hasClearTrend ? scheme.error : null,
                ),
              ),
              for (final t in report.trends.skip(1))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• ${t.text}', style: theme.textTheme.bodyMedium),
                ),
              if (total > 0) ...[
                const SizedBox(height: 14),
                for (final k in StemKind.values)
                  if (report.counts[k]! > 0) _KindBar(kind: k, count: report.counts[k]!, total: total),
              ],
              if (report.templates.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Tekrar eden kalıplar', style: theme.textTheme.titleSmall),
                for (final t in report.templates)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '"${t.example}" — ${t.count} kez (${t.wrong} yanlış, ${t.blank} boş'
                      '${t.careless > 0 ? ', ${t.careless} dikkatsizlik' : ''})',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                'Soru cümleleri fotoğraflardan otomatik okunur. Defterde çoğunlukla yanlışlar olduğu için '
                'oranlar yanlışların içindeki paylardır; fotoğraflı doğru sorular biriktikçe gerçek hata '
                'oranı da karşılaştırılır. Eğilim için her grupta en az $minGroup soru, en az 15 puan fark '
                've anlamlılık (z ≥ 2) aranır.',
                style: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindBar extends StatelessWidget {
  const _KindBar({required this.kind, required this.count, required this.total});
  final StemKind kind;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = kind == StemKind.negative ? theme.colorScheme.error : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(kind.label, style: theme.textTheme.bodyMedium)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: count / total,
                minHeight: 8,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(width: 44, child: Text('$count', textAlign: TextAlign.end, style: theme.textTheme.labelLarge)),
        ],
      ),
    );
  }
}
