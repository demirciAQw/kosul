import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/presentation/question_prefill.dart';
import '../../question_bank/presentation/widgets/question_tile.dart';
import '../../question_bank/question_bank_providers.dart';
import '../domain/progress.dart';
import '../library_providers.dart';
import 'book_detail_screen.dart' show toggleSolved;
import 'test_mark_flow.dart';
import 'widgets/progress_widgets.dart';

/// Tek bir testin ekranı: sonucu, yanlışlarının optiği ve fotoğrafları.
/// Optik buradan açılıp düzeltilebilir; test elle çözüldü/çözülmedi yapılabilir.
class TestDetailScreen extends ConsumerWidget {
  const TestDetailScreen({super.key, required this.bookId, required this.nodeId});

  final String bookId;
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookByIdProvider(bookId));
    final node = book == null ? null : findNode(book, nodeId);
    if (book == null || node == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Test bulunamadı.')));
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = (ref.watch(testResultsProvider).value ?? const <String, TestResult>{})[nodeId];
    final cards = ref.watch(cardsForNodeProvider(nodeId)).value ?? const <QuestionCard>[];
    final mistakes = [for (final c in cards) if (c.status != QuestionStatus.correct) c];
    final byNo = {
      for (final c in mistakes)
        if (c.questionNo != null) c.questionNo!: c,
    };
    final highest = byNo.keys.fold<int>(0, (a, b) => a > b ? a : b);
    final total = node.questionCount ?? result?.total ?? highest;
    final path = pathTo(book, nodeId);

    return Scaffold(
      appBar: AppBar(title: Text(node.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(
            [book.title, ...path.take(path.length - 1).map((n) => n.title)].join(' › '),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(color: testColor(context, result), borderRadius: BorderRadius.circular(5)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result == null ? 'Henüz çözülmedi' : 'Çözüldü, ${formatDate(result.solvedAt)}',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          [
                            if (node.questionCount != null) '${node.questionCount} soru',
                            if (node.hasPages) 'sayfa ${node.pageStart}–${node.pageEnd}',
                            if (result != null && result.hasCounts)
                              '${result.correct ?? 0} D, ${result.wrong ?? 0} Y, ${result.blank ?? 0} B',
                          ].join(', '),
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (result != null && result.hasCounts) ...[
                          const SizedBox(height: 8),
                          ResultBar(correct: result.correct ?? 0, wrong: result.wrong ?? 0, blank: result.blank ?? 0),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => markBookScope(context, ref, book: book, node: node),
                  icon: const Icon(Icons.checklist_rounded),
                  label: Text(result == null ? 'Optikle işaretle' : 'Optiği düzenle'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => toggleSolved(
                    context,
                    ref,
                    book: book,
                    node: node,
                    current: result,
                    solved: result == null,
                  ),
                  icon: Icon(result == null ? Icons.check_rounded : Icons.undo_rounded),
                  label: Text(result == null ? 'Çözüldü yap' : 'Çözülmedi yap'),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 20),
            Text('Optik', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'İşaretli numaraya dokun: soruyu aç. Boş numaraya dokun: o numarayla soru ekle.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 52,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: total,
              itemBuilder: (context, i) {
                final no = i + 1;
                final card = byNo[no];
                return _ReadOnlyBubble(
                  number: no,
                  status: card?.status,
                  onTap: card != null
                      ? () => context.push(AppRoutes.question(card.id))
                      : () => _addQuestion(context, ref, questionNo: no),
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text('Yanlış ve boşlar (${mistakes.length})', style: theme.textTheme.titleSmall),
              ),
              TextButton.icon(
                onPressed: () => _addQuestion(context, ref),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Soru ekle'),
              ),
            ],
          ),
          if (mistakes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                result == null
                    ? 'Testi çözünce optikten yanlışlarını işaretle; burada fotoğraflarıyla görünürler.'
                    : 'Bu testte defterde yanlış ya da boş soru yok.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 3 / 4,
              ),
              itemCount: mistakes.length,
              itemBuilder: (context, i) => QuestionTile(card: mistakes[i]),
            ),
        ],
      ),
    );
  }

  void _addQuestion(BuildContext context, WidgetRef ref, {int? questionNo}) {
    final book = ref.read(bookByIdProvider(bookId));
    final node = book == null ? null : findNode(book, nodeId);
    if (book == null || node == null) return;
    context.push(
      AppRoutes.newQuestion,
      extra: QuestionPrefill(
        origin: QuestionOrigin.book,
        bookId: book.id,
        contentNodeId: node.id,
        sourceName: book.title,
        subject: subjectKey(book.examType, book.subject),
        mebNodeId: effectiveMeb(book, node.id),
        testLabel: nodeLabel(book, node.id),
        testTotalQuestions: node.questionCount,
        questionNo: questionNo,
      ),
    );
  }
}

class _ReadOnlyBubble extends StatelessWidget {
  const _ReadOnlyBubble({required this.number, required this.status, required this.onTap});

  final int number;
  final QuestionStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = status;
    final fill = s == null ? Colors.transparent : statusColor(s);
    return Material(
      color: fill,
      shape: CircleBorder(side: BorderSide(color: s == null ? scheme.outlineVariant : fill, width: 1.5)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Center(
          child: Text(
            '$number',
            style: TextStyle(
              color: s == null ? scheme.onSurfaceVariant : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
