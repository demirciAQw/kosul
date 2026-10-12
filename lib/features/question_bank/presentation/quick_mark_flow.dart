import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/quick_mark.dart';
import '../question_bank_providers.dart';
import 'screens/optic_form_screen.dart';

/// Önceki işaretlerle optik formu açar, sonucu defterle eşitler.
///
/// Dönen sonuç (D/Y/B) çağıran tarafça oturum bloğuna ya da deneme dersine
/// yazılır. Vazgeçilirse ya da kayıt başarısız olursa null.
Future<OpticFormResult?> openQuickMark(
  BuildContext context,
  WidgetRef ref, {
  required QuickMarkContext markContext,
  required String title,
  required int initialTotal,
  String? subtitle,
  bool totalEditable = true,
  bool showNet = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final quick = ref.read(quickMarkProvider);
  final existing = await quick.existingMarks(markContext);
  if (!context.mounted) return null;

  final highestMarked = existing.keys.fold<int>(0, math.max);
  final result = await OpticFormScreen.open(
    context,
    title: title,
    subtitle: subtitle,
    initialTotal: math.max(math.max(initialTotal, highestMarked), 1),
    totalEditable: totalEditable,
    initialMarks: existing,
    showNet: showNet,
  );
  if (result == null) return null;

  try {
    final summary = await quick.call(markContext, total: result.total, marks: result.marks);
    messenger.showSnackBar(SnackBar(content: Text(summary.message)));
    return result;
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('İşaretler kaydedilemedi: $e')));
    return null;
  }
}
