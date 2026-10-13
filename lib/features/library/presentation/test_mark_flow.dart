import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../curriculum/domain/curriculum.dart';
import '../../question_bank/domain/question_card.dart';
import '../../question_bank/domain/quick_mark.dart';
import '../../question_bank/presentation/quick_mark_flow.dart';
import '../../question_bank/presentation/screens/optic_form_screen.dart';
import '../domain/library.dart';
import '../domain/progress.dart';
import '../library_providers.dart';

/// Kitaptaki bir kapsamın optiği: tek test, çok testli bir bölüm ya da tüm kitap
/// ([node] null). Testi olan kapsamlarda form test test bölünür; her testin
/// numarası 1'den başlar ve kartlar o teste bağlanır ("6. test, 5. soru").
///
/// Dahil edilen her test, sayılarıyla "çözüldü" olarak kitap haritasına yazılır.
/// Oturum içinden çağrılırsa [sessionId] / [sessionItemId] kartlara işlenir.
Future<OpticFormResult?> markBookScope(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
  ContentNode? node,
  String? sessionId,
  String? sessionItemId,
  double? avgSecondsPerQuestion,
  int? fallbackTotal,
}) async {
  final leaves = node == null ? progressLeaves(book) : leavesUnder(node);
  final tests = leaves.any((l) => l.questionCount == null) ? const <ContentNode>[] : leaves;
  final subject = subjectKey(book.examType, book.subject);

  QuickMarkContext contextFor(ContentNode? target, {required bool byNode}) => QuickMarkContext(
        origin: QuestionOrigin.book,
        subject: subject,
        sourceName: book.title,
        bookId: book.id,
        contentNodeId: target?.id,
        mebNodeId: target == null ? null : effectiveMeb(book, target.id),
        sessionId: sessionId,
        sessionItemId: sessionItemId,
        testLabel: target == null ? null : nodeLabel(book, target.id),
        avgSecondsPerQuestion: avgSecondsPerQuestion,
        linkByTest: byNode,
      );

  final List<QuickMarkPart> parts;
  if (tests.isNotEmpty) {
    parts = [
      for (final t in tests)
        QuickMarkPart(
          key: t.id,
          title: t.title,
          total: t.questionCount!,
          markContext: contextFor(t, byNode: true),
        ),
    ];
  } else {
    // Test yapısı olmayan kapsam: tek bölüm. Yaprak başlıksa (ör. "Öğrendiğini
    // Uygula") ona bağlanır; daha büyük bir bloksa oturum bloğuna bağlanır.
    final isLeaf = node != null && node.children.isEmpty;
    final pages = node == null || !node.hasPages ? book.pageCount : node.pageEnd! - node.pageStart! + 1;
    parts = [
      QuickMarkPart(
        key: node?.id ?? book.id,
        title: node?.title ?? book.title,
        total: fallbackTotal ?? book.estimateQuestions(pages),
        markContext: contextFor(node, byNode: isLeaf || sessionItemId == null),
      ),
    ];
  }

  final result = await openQuickMark(
    context,
    ref,
    parts: parts,
    title: node == null ? book.title : node.title,
    subtitle: node == null ? null : '${book.title}, ${nodeLabel(book, node.id)}',
  );
  if (result == null) return null;

  // Kitap haritası: çözülen testler sayılarıyla, test yapısı olmayan kapsamda
  // yapraklar sayısız işaretlenir.
  final progress = ref.read(testProgressRepositoryProvider);
  final now = ref.read(clockProvider)();
  try {
    if (tests.isNotEmpty) {
      for (var i = 0; i < tests.length; i++) {
        final s = result.sections[i];
        if (!s.included) continue;
        await progress.save(TestResult(
          nodeId: tests[i].id,
          bookId: book.id,
          solvedAt: now,
          correct: s.correct,
          wrong: s.wrong,
          blank: s.blank,
          total: s.total,
          sessionId: sessionId,
        ));
      }
    } else if (result.sections.first.included) {
      final s = result.sections.first;
      if (leaves.length == 1) {
        await progress.save(TestResult(
          nodeId: leaves.single.id,
          bookId: book.id,
          solvedAt: now,
          correct: s.correct,
          wrong: s.wrong,
          blank: s.blank,
          total: s.total,
          sessionId: sessionId,
        ));
      } else {
        await progress.saveIfAbsent([
          for (final l in leaves) TestResult(nodeId: l.id, bookId: book.id, solvedAt: now, sessionId: sessionId),
        ]);
      }
    }
  } on Exception catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test durumu kaydedilemedi: $e')));
    }
  }
  return result;
}
