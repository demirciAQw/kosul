import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/palette.dart';
import '../../../app/routes.dart';
import '../../../app/widgets/tone_icon.dart';
import '../../../core/utils/formatters.dart';
import '../domain/notes.dart';
import '../notes_providers.dart';

/// Defter › Notlar: her dersin kendi not defteri. Üstte ders seçimi, altta
/// derslere göre gruplu notlar (sabitlenenler başta).
class NotesView extends ConsumerWidget {
  const NotesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    final selected = ref.watch(noteSubjectFilterProvider);
    return notes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Notlar yüklenemedi: $e')),
      data: (all) {
        if (all.isEmpty) return const _EmptyNotes();
        final counts = <String, int>{};
        for (final n in all) {
          counts[n.subject] = (counts[n.subject] ?? 0) + 1;
        }
        final subjects = counts.keys.toList()..sort();
        final current = selected != null && counts.containsKey(selected) ? selected : null;
        final visible = [for (final n in all) if (current == null || n.subject == current) n];
        final groups = <String, List<StudyNote>>{};
        for (final n in visible) {
          (groups[n.subject] ??= []).add(n);
        }
        final ordered = groups.keys.toList()..sort();

        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('Tüm dersler (${all.length})'),
                    selected: current == null,
                    onSelected: (_) => ref.read(noteSubjectFilterProvider.notifier).set(null),
                  ),
                  for (final s in subjects) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('$s (${counts[s]})'),
                      selected: current == s,
                      onSelected: (on) => ref.read(noteSubjectFilterProvider.notifier).set(on ? s : null),
                    ),
                  ],
                ],
              ),
            ),
            for (final (i, subject) in ordered.indexed) ...[
              _SubjectHeader(subject: subject, count: groups[subject]!.length, color: KocumColors.accents[i % 4]),
              for (final n in groups[subject]!)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _NoteCard(note: n),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _SubjectHeader extends StatelessWidget {
  const _SubjectHeader({required this.subject, required this.count, required this.color});
  final String subject;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          ToneIcon(Icons.menu_book_rounded, color: color, size: 32),
          const SizedBox(width: 10),
          Expanded(child: Text('$subject defteri', style: theme.textTheme.titleSmall)),
          Text('$count not', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note});
  final StudyNote note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = note;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.note(n.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (n.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.push_pin_rounded, size: 16, color: scheme.primary),
                          ),
                        Expanded(
                          child: Text(n.heading,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${formatDate(n.createdAt)}, ${formatClock(n.createdAt)}${n.wasEdited ? ' (düzenlendi)' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Not seçenekleri',
                onSelected: (a) => a == 'pin'
                    ? ref.read(noteRepositoryProvider).setPinned(n.id, !n.isPinned)
                    : deleteNoteWithUndo(context, ref, n),
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'pin', child: Text(n.isPinned ? 'Sabitlemeyi kaldır' : 'Başa sabitle')),
                  const PopupMenuItem(value: 'delete', child: Text('Notu sil')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notu siler; "Geri al" ile aynen geri gelir.
Future<void> deleteNoteWithUndo(BuildContext context, WidgetRef ref, StudyNote note) async {
  final repo = ref.read(noteRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  await repo.delete(note.id);
  messenger.showSnackBar(SnackBar(
    content: const Text('Not silindi.'),
    action: SnackBarAction(label: 'Geri al', onPressed: () => repo.save(note)),
  ));
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ToneIcon(Icons.sticky_note_2_outlined, color: KocumColors.blue, size: 64),
            const SizedBox(height: 16),
            Text('Henüz not yok', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Not ekle ile başla. Tarih ve saat kendiliğinden yazılır; not seçtiğin dersin defterine düşer.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
