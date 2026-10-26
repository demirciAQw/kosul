import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../dashboard_providers.dart';
import '../domain/dashboard.dart';
import '../domain/patterns.dart';
import 'ai_report_sheet.dart';
import 'deep_analysis_section.dart';
import 'stem_analysis_section.dart';

/// "En çok hangi konuda/nedenden yanlış yapıyorum ve ne kadar süre kaybediyorum?"
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dimension = ref.watch(dashboardDimensionProvider);
    final range = ref.watch(dashboardRangeProvider);
    final stats = ref.watch(mistakeStatsProvider);
    final daily = ref.watch(dailyStudyProvider);
    final patterns = ref.watch(subjectPatternsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analiz'),
        actions: [
          TextButton.icon(
            onPressed: () => showAiReportSheet(context),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Yapay zekâ raporu'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 gün')),
              ButtonSegment(value: 30, label: Text('30 gün')),
              ButtonSegment(value: 90, label: Text('90 gün')),
              ButtonSegment(value: 0, label: Text('Tümü')),
            ],
            selected: {range},
            onSelectionChanged: (s) => ref.read(dashboardRangeProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 20),
          const DeepAnalysisSection(),
          const StemAnalysisSection(),
          const SizedBox(height: 28),
          Text('Derslere göre örüntüler', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          patterns.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('Örüntüler okunamadı: $e'),
            data: (list) => _PatternSection(patterns: list),
          ),
          const SizedBox(height: 28),
          Text('En çok yanlış', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<MistakeDimension>(
            segments: [for (final d in MistakeDimension.values) ButtonSegment(value: d, label: Text(d.label))],
            selected: {dimension},
            onSelectionChanged: (s) => ref.read(dashboardDimensionProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 16),
          stats.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Analiz yüklenemedi: $e'),
            data: (list) => _MistakeSection(stats: list, dimension: dimension),
          ),
          const SizedBox(height: 28),
          daily.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('Çalışma süresi okunamadı: $e'),
            data: (days) => _StudyChart(days: days),
          ),
        ],
      ),
    );
  }
}

class _PatternSection extends StatelessWidget {
  const _PatternSection({required this.patterns});
  final List<SubjectPattern> patterns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (patterns.isEmpty) {
      return Text(
        'Bir derste en az 3 yanlış ya da boş biriktiğinde, hangi konuda ve hangi nedenle '
        'kaçırdığın burada yazılır.',
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      children: [
        for (final p in patterns.take(5))
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(p.subject, style: theme.textTheme.titleSmall)),
                      Text('${p.mistakes} yanlış ve boş',
                          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final line in p.insights)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(line, style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MistakeSection extends StatelessWidget {
  const _MistakeSection({required this.stats, required this.dimension});
  final List<LabeledStat> stats;
  final MistakeDimension dimension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (stats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.insights_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Henüz analiz edilecek yanlış yok', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Yanlış ve boş soruları ekledikçe burada görünür.', textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final total = stats.fold<int>(0, (sum, s) => sum + s.count);
    final lost = stats.fold<double>(0, (sum, s) => sum + s.lostSeconds);
    final maxCount = stats.map((s) => s.count).reduce(math.max);
    final maxLost = stats.map((s) => s.lostSeconds).reduce(math.max);
    final top = stats.first;
    final what = switch (dimension) {
      MistakeDimension.topic => 'konusunda',
      MistakeDimension.reason => 'nedeni',
      MistakeDimension.subject => 'dersinde',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _Figure(value: '$total', label: 'yanlış ve boş soru')),
            Expanded(
              child: _Figure(
                value: lost > 0 ? '≈ ${formatApproxDuration(lost)}' : '–',
                label: 'tahmini kayıp süre',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'En çok yanlışın "${top.label}" $what: ${top.count} soru'
              '${top.lostSeconds > 0 ? ', yaklaşık ${formatApproxDuration(top.lostSeconds)} kayıp' : ''}.',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final s in stats.take(10))
          _BarRow(stat: s, maxCount: maxCount, maxLost: maxLost),
        const SizedBox(height: 8),
        Text(
          'Kayıp süre = yanlış sayısı × o testteki soru başına ortalama süre. Yaklaşık bir değerdir.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineMedium),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.stat, required this.maxCount, required this.maxLost});
  final LabeledStat stat;
  final int maxCount;
  final double maxLost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(stat.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
              const SizedBox(width: 8),
              Text('${stat.count} soru', style: theme.textTheme.labelLarge),
            ],
          ),
          if (stat.sublabel != null)
            Text(stat.sublabel!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: stat.count / maxCount,
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          if (stat.lostSeconds > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: maxLost == 0 ? 0 : stat.lostSeconds / maxLost,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: scheme.tertiary,
              backgroundColor: scheme.tertiaryContainer.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 2),
            Text('≈ ${formatApproxDuration(stat.lostSeconds)} kayıp',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _StudyChart extends StatelessWidget {
  const _StudyChart({required this.days});
  final List<DailyStudy> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxSeconds = days.map((d) => d.duration.inSeconds).fold<int>(0, math.max);
    final total = days.fold<int>(0, (sum, d) => sum + d.duration.inSeconds);
    const barArea = 96.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Son 7 gün çalışma süresi', style: theme.textTheme.titleMedium),
        Text('Toplam ${formatDuration(Duration(seconds: total))}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        SizedBox(
          height: barArea + 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(d.duration.inMinutes == 0 ? '' : '${d.duration.inMinutes}', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Container(
                        height: maxSeconds == 0 ? 3 : math.max(3, barArea * d.duration.inSeconds / maxSeconds),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: d.duration.inSeconds == 0 ? scheme.outlineVariant : scheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(weekdayShort(d.day), style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Text('Sütun üstündeki sayılar dakikadır.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
