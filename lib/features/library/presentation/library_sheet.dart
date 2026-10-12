import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_data.dart';
import '../domain/book_template_usecases.dart';
import '../domain/library.dart';
import '../library_providers.dart';

const sampleTemplateAsset = 'assets/templates/345_TYT_Mat.json';
const _sampleTitle = '345 TYT Matematik Soru Bankası';

String _reportMessage(ImportReport report) {
  final review = report.needsReview > 0 ? ', ${report.needsReview} başlık onayını bekliyor' : '';
  return '${report.book.title} eklendi. ${report.matched} başlık MEB konusuyla eşleşti$review.';
}

/// Dosya seç → doğrula → MEB'e normalize et → kaydet. Hata mesajı, JSON'daki
/// sorunun tam yolunu içerir (ör. "$.units[2].pageEnd").
Future<void> importBookTemplateFlow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final raw = await ref.read(templateFileGatewayProvider).pickTemplateJson();
    if (raw == null) return;
    final report = await ref.read(importBookTemplateProvider).call(raw);
    messenger.showSnackBar(SnackBar(content: Text(_reportMessage(report))));
  } on BookTemplateException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Şablon içe aktarılamadı: ${e.message}')));
  }
}

/// Uygulamayla gelen örnek kitabı tek dokunuşla ekler (denemek için).
Future<void> importSampleBookFlow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final books = ref.read(libraryProvider).value ?? const <Book>[];
  if (books.any((b) => b.title == _sampleTitle)) {
    messenger.showSnackBar(const SnackBar(content: Text('Örnek kitap zaten ekli.')));
    return;
  }
  try {
    final raw = await rootBundle.loadString(sampleTemplateAsset);
    final report = await ref.read(importBookTemplateProvider).call(raw);
    messenger.showSnackBar(SnackBar(content: Text(_reportMessage(report))));
  } on BookTemplateException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Örnek kitap eklenemedi: ${e.message}')));
  }
}

Future<void> exportBookTemplateFlow(WidgetRef ref, ScaffoldMessengerState messenger, Book book) async {
  try {
    final json = await ref.read(exportBookTemplateProvider).call(book.id);
    await ref
        .read(templateFileGatewayProvider)
        .share(fileName: TemplateFileGateway.fileNameFor(book), json: json);
  } on Exception catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Şablon paylaşılamadı: $e')));
  }
}

Future<void> showLibrarySheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _LibrarySheet(),
    );

class _LibrarySheet extends ConsumerWidget {
  const _LibrarySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final books = ref.watch(libraryProvider).value ?? const <Book>[];
    final messenger = ScaffoldMessenger.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Kitaplarım', style: theme.textTheme.titleLarge),
              trailing: TextButton.icon(
                onPressed: () => importBookTemplateFlow(context, ref),
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('JSON içe aktar'),
              ),
            ),
            if (books.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  children: [
                    const Text('Henüz kitap yok. Bir JSON şablonu içe aktararak başla.'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => importSampleBookFlow(context, ref),
                      child: const Text('Örnek kitabı ekle'),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final b in books)
                      ListTile(
                        title: Text(b.title),
                        subtitle: Text('${b.examType} ${b.subject}, ${b.pageCount} sayfa, '
                            '${b.allNodes.length} başlık'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'share') {
                              await exportBookTemplateFlow(ref, messenger, b);
                            } else {
                              await _confirmDelete(context, ref, b);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'share', child: Text('Şablonu paylaş (JSON)')),
                            PopupMenuItem(value: 'delete', child: Text('Kitabı sil')),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Kitabı sil?'),
        content: const Text(
          'Kitap ve içindekiler silinir. Bu kitaptan eklediğin sorular defterinde kalır, '
          'yalnızca kitapla bağı kopar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) await ref.read(libraryRepositoryProvider).delete(book.id);
  }
}
