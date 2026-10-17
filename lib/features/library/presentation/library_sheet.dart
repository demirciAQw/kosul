import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_data.dart';
import '../domain/book_template_usecases.dart';
import '../domain/library.dart';
import '../library_providers.dart';

const _templateFolder = 'assets/templates/';

/// Uygulamayla gelen hazır kitap şablonu.
class BundledTemplate {
  const BundledTemplate({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.shelf,
    this.isSample = false,
  });

  final String asset;
  final String title;
  final String subtitle;

  /// "TYT", "AYT" ya da "MEB": listede başlık olarak kullanılır.
  final String shelf;

  /// Yalnızca denemek için hazırlanmış örnek veri.
  final bool isSample;
}

/// assets/templates/ altındaki tüm şablonlar; klasöre yeni JSON konunca kendiliğinden görünür.
final bundledTemplatesProvider = FutureProvider<List<BundledTemplate>>((ref) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets = manifest.listAssets().where((a) => a.startsWith(_templateFolder) && a.endsWith('.json')).toList()
    ..sort();
  final out = <BundledTemplate>[];
  for (final asset in assets) {
    try {
      final json = jsonDecode(await rootBundle.loadString(asset)) as Map<String, dynamic>;
      final book = json['book'] as Map<String, dynamic>;
      final sample = json['author'] == 'ornek_kullanici';
      final isMeb = (book['publisher'] as String? ?? '').trim().toUpperCase() == 'MEB';
      out.add(BundledTemplate(
        shelf: isMeb ? 'MEB' : (book['examType'] == 'TYT' ? 'TYT' : 'AYT'),
        asset: asset,
        title: book['title'] as String,
        subtitle: '${book['examType']} ${book['subject']}, ${book['pageCount']} sayfa'
            '${sample ? ' (deneme amaçlı örnek)' : ''}',
        isSample: sample,
      ));
    } catch (_) {
      // Bozuk bir şablon listeyi düşürmesin.
    }
  }
  const order = {'TYT': 0, 'AYT': 1, 'MEB': 2};
  out.sort((a, b) {
    if (a.isSample != b.isSample) return a.isSample ? 1 : -1;
    final s = (order[a.shelf] ?? 9).compareTo(order[b.shelf] ?? 9);
    return s != 0 ? s : a.title.compareTo(b.title);
  });
  return out;
});

String _reportMessage(ImportReport report) {
  final review = report.needsReview > 0 ? ', ${report.needsReview} başlık onayını bekliyor' : '';
  final matched = report.matched > 0 ? ' ${report.matched} başlık MEB konusuyla eşleşti$review.' : '';
  return '${report.book.title} eklendi.$matched';
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

/// Uygulamayla gelen bir şablonu tek dokunuşla ekler.
Future<void> importBundledTemplateFlow(BuildContext context, WidgetRef ref, BundledTemplate template) async {
  final messenger = ScaffoldMessenger.of(context);
  final books = ref.read(libraryProvider).value ?? const <Book>[];
  if (books.any((b) => b.title == template.title)) {
    messenger.showSnackBar(SnackBar(content: Text('${template.title} zaten ekli.')));
    return;
  }
  try {
    final raw = await rootBundle.loadString(template.asset);
    final report = await ref.read(importBookTemplateProvider).call(raw);
    messenger.showSnackBar(SnackBar(content: Text(_reportMessage(report))));
  } on BookTemplateException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Kitap eklenemedi: ${e.message}')));
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
    final templates = ref.watch(bundledTemplatesProvider).value ?? const <BundledTemplate>[];
    final owned = {for (final b in books) b.title};
    final messenger = ScaffoldMessenger.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
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
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  if (books.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Text('Henüz kitap yok. Aşağıdaki hazır kitaplardan ekle ya da bir JSON şablonu içe aktar.'),
                    ),
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
                  if (templates.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text('Hazır kitaplar', style: theme.textTheme.titleMedium),
                    ),
                  for (final (i, t) in templates.indexed) ...[
                    if (i == 0 || templates[i - 1].shelf != t.shelf)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                        child: Text(
                          '${t.shelf} kitapları',
                          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                    ListTile(
                      leading: Icon(
                        owned.contains(t.title) ? Icons.check_circle_rounded : Icons.library_add_outlined,
                        color: owned.contains(t.title) ? theme.colorScheme.primary : null,
                      ),
                      title: Text(t.title),
                      subtitle: Text(t.subtitle),
                      trailing: owned.contains(t.title)
                          ? const Text('Ekli')
                          : FilledButton.tonal(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                              onPressed: () => importBundledTemplateFlow(context, ref, t),
                              child: const Text('Ekle'),
                            ),
                    ),
                  ],
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
