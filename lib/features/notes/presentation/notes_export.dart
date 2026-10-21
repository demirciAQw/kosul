import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/export/zip_writer.dart';
import '../domain/notes.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _stamp(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

/// Notların Markdown metni: derslere göre, tarih ve saatiyle; fotoğraflara bağlantı.
String notesMarkdown(List<StudyNote> notes, Map<String, List<String>> photoNames, {required String title}) {
  final bySubject = <String, List<StudyNote>>{};
  for (final n in notes) {
    (bySubject[n.subject] ??= []).add(n);
  }
  final b = StringBuffer('# $title\n');
  for (final subject in bySubject.keys.toList()..sort()) {
    b.write('\n## $subject\n');
    final list = bySubject[subject]!..sort((x, y) => x.createdAt.compareTo(y.createdAt));
    for (final n in list) {
      b.write('\n### ${n.heading.isEmpty ? 'Not' : n.heading}\n_${_stamp(n.createdAt)}_\n');
      if (n.body.isNotEmpty) b.write('\n${n.body}\n');
      for (final p in photoNames[n.id] ?? const <String>[]) {
        b.write('\n![]($p)\n');
      }
    }
  }
  return b.toString();
}

/// Notları ve sayfa fotoğraflarını tek ZIP olarak paylaşır.
Future<void> exportNotes(BuildContext context, WidgetRef ref, List<StudyNote> notes, {required String title}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (notes.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Dışa aktarılacak not yok.')));
    return;
  }
  final media = ref.read(mediaStorageProvider);
  try {
    final zip = ZipWriter();
    final names = <String, List<String>>{};
    for (final n in notes) {
      final folder = safeFileName(n.subject);
      final when = '${n.createdAt.year}-${_two(n.createdAt.month)}-${_two(n.createdAt.day)}_${_two(n.createdAt.hour)}${_two(n.createdAt.minute)}';
      final head = n.heading.isEmpty ? '' : '_${safeFileName(n.heading, maxLength: 40)}';
      for (final (i, p) in n.photos.indexed) {
        final file = media.resolve(p);
        if (!await file.exists()) continue;
        final dot = p.lastIndexOf('.');
        final ext = dot < 0 ? '.jpg' : p.substring(dot);
        final added = zip.add('$folder/$when${head}_s${i + 1}$ext', await file.readAsBytes());
        (names[n.id] ??= []).add(added);
      }
    }
    zip.addText('notlar.md', notesMarkdown(notes, names, title: title));
    final now = DateTime.now();
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/Kocum_Notlar_${now.year}-${_two(now.month)}-${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}.zip');
    await out.writeAsBytes(zip.finish(), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(out.path, mimeType: 'application/zip')],
      subject: 'Koçum notları',
      text: '$title: ${notes.length} not',
    ));
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Dışa aktarılamadı: $e')));
  }
}
