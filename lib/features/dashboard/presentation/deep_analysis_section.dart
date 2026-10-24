import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/palette.dart';
import '../../../app/widgets/tone_icon.dart';
import '../dashboard_providers.dart';
import '../domain/deep_analysis.dart';

/// Derin analiz: aynı koşullarda tekrar tekrar görülen farklar. Az veriyle
/// yorum yapmaz; neyin sabit tutulduğunu ve kaç gün, kaç soruya dayandığını söyler.
class DeepAnalysisSection extends ConsumerWidget {
  const DeepAnalysisSection({super.key});

  static const _icons = {
    Factor.timeOfDay: Icons.schedule_rounded,
    Factor.dayType: Icons.calendar_month_outlined,
    Factor.pace: Icons.speed_rounded,
    Factor.sessionLength: Icons.timer_outlined,
    Factor.source: Icons.menu_book_rounded,
    Factor.topic: Icons.category_outlined,
    Factor.period: Icons.trending_up_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final analysis = ref.watch(deepAnalysisProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Derin analiz', style: theme.textTheme.titleMedium)),
            IconButton(
              tooltip: 'Nasıl hesaplanıyor?',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('Nasıl hesaplanıyor?'),
                  content: const SingleChildScrollView(
                    child: Text(
                      'Her etken (saat, gün, hız, oturum uzunluğu, kaynak, konu, zaman) ayrı ayrı incelenir. '
                      'Karşılaştırma yalnızca diğer koşullar aynıyken yapılır: örneğin saatin etkisi için '
                      'aynı ders ve aynı kaynaktaki çözümler kendi içinde karşılaştırılır.\n\n'
                      'Az veriyle yorum yapılmaz. Bir sonucun gösterilmesi için her grupta en az 30 soru ve '
                      'en az 3 farklı gün olmalı, fark en az 8 puan ve istatistiksel olarak güvenilir olmalı. '
                      'Birden çok grupta incelendiyse farkın çoğunda aynı yönde tekrarlanması gerekir.\n\n'
                      'Hız, her dersin kendi ortalama süresine göre ölçülür.',
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Tamam'))],
                ),
              ),
            ),
          ],
        ),
        analysis.when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          error: (e, _) => Text('Analiz yapılamadı: $e'),
          data: (a) {
            if (a.findings.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const ToneIcon(Icons.hourglass_bottom_rounded, color: KocumColors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Henüz güvenilir bir sonuç yok. Şu an ${a.days} günde ${a.questions} soru kayıtlı. '
                          'Bir karşılaştırma için her grupta en az 30 soru ve 3 farklı gün gerekiyor; '
                          'oturumlarda sonuçları girmeye devam et.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final (i, f) in a.findings.indexed)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ToneIcon(_icons[f.factor]!, color: KocumColors.accents[i % 4]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.factor.title,
                                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text(f.sentence, style: theme.textTheme.bodyLarge),
                                const SizedBox(height: 4),
                                Text(f.evidence,
                                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
