import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/question_card.dart';
import '../domain/quick_mark.dart';
import '../question_bank_providers.dart';
import 'question_prefill.dart';
import 'screens/add_question_screen.dart';
import 'screens/optic_form_screen.dart';

/// Optik formun bir bölümü ve o bölümün işaretlerinin bağlanacağı yer.
class QuickMarkPart {
  const QuickMarkPart({
    required this.key,
    required this.title,
    required this.total,
    required this.markContext,
    this.start = 1,
    this.initiallyIncluded = true,
  });

  final String key;
  final String title;
  final int total;

  /// İlk soru numarası (kitapçıkta testi paylaşan dersler için).
  final int start;
  final QuickMarkContext markContext;
  final bool initiallyIncluded;
}

/// Önceki işaretlerle optik formu açar ve her bölümü defterle eşitler.
///
/// Dönen sonuçtaki sayılar (D/Y/B) çağıran tarafça oturum bloğuna, deneme
/// dersine ya da test sonucuna yazılır. Vazgeçilirse ya da kayıt başarısız
/// olursa null.
Future<OpticFormResult?> openQuickMark(
  BuildContext context,
  WidgetRef ref, {
  required List<QuickMarkPart> parts,
  required String title,
  String? subtitle,
  bool totalEditable = true,
  bool showNet = false,
  /// Önce görüntüleme modu: numaraya dokununca soru ekranı açılır.
  bool viewFirst = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final quick = ref.read(quickMarkProvider);
  final sections = <OpticSection>[];
  for (final part in parts) {
    final existing = await quick.existingMarks(part.markContext);
    final highest = existing.keys.fold<int>(0, math.max);
    sections.add(OpticSection(
      key: part.key,
      title: part.title,
      start: part.start,
      // Tek bölümde, aralığın ötesinde işaret varsa form onu da gösterecek kadar büyür.
      total: part.start == 1 ? math.max(math.max(part.total, highest), 1) : part.total,
      initialMarks: existing,
      initiallyIncluded: part.initiallyIncluded,
    ));
  }
  if (!context.mounted) return null;

  final navigator = Navigator.of(context, rootNavigator: true);

  /// Görüntüleme modunda numaraya dokunulunca: kart varsa düzenleme, yoksa
  /// kaynak, ders, soru no ve durumla dolu ekleme ekranı. Dönüşte güncel durum.
  Future<QuestionStatus?> openQuestion(OpticSection section, int number, QuestionStatus? mark) async {
    final part = parts.firstWhere((p) => p.key == section.key);
    final ctx = part.markContext;
    final existing = await quick.cardAt(ctx, number);
    await navigator.push<void>(MaterialPageRoute(
      builder: (_) => existing != null
          ? AddQuestionScreen(editCardId: existing.id)
          : AddQuestionScreen(
              prefill: QuestionPrefill(
                origin: ctx.origin,
                status: mark ?? QuestionStatus.wrong,
                sourceName: ctx.sourceName,
                bookId: ctx.bookId,
                contentNodeId: ctx.contentNodeId,
                sessionId: ctx.sessionId,
                sessionItemId: ctx.sessionItemId,
                mockExamId: ctx.mockExamId,
                mebNodeId: ctx.mebNodeId,
                subject: ctx.subject,
                testTotalQuestions: part.total,
                avgSecondsPerQuestion: ctx.avgSecondsPerQuestion,
                testLabel: ctx.testLabel,
                questionNo: number,
              ),
            ),
    ));
    final after = await quick.cardAt(ctx, number);
    if (after == null) return existing == null ? mark : null;
    return after.status == QuestionStatus.correct ? null : after.status;
  }

  final result = await OpticFormScreen.open(
    context,
    title: title,
    subtitle: subtitle,
    sections: sections,
    onOpenQuestion: viewFirst ? openQuestion : null,
    totalEditable: totalEditable && parts.length == 1,
    showNet: showNet,
  );
  if (result == null) return null;

  try {
    var summary = QuickMarkSummary.zero;
    for (var i = 0; i < parts.length; i++) {
      final section = result.sections[i];
      if (!section.included) continue;
      summary += await quick.call(
        parts[i].markContext,
        total: section.total,
        first: section.start,
        marks: section.marks,
      );
    }
    messenger.showSnackBar(SnackBar(content: Text(summary.message)));
    return result;
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('İşaretler kaydedilemedi: $e')));
    return null;
  }
}
