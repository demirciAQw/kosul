import '../../../core/text/turkish_text.dart';
import '../../curriculum/domain/curriculum.dart';
import 'question_card.dart';

enum GroupBy {
  subject('Ders'),
  book('Kitap'),
  topic('Konu');

  const GroupBy(this.label);
  final String label;
}

class QuestionGroup {
  QuestionGroup({required this.title, this.subtitle});

  final String title;
  final String? subtitle;
  final List<QuestionCard> cards = [];
  final List<QuestionGroup> children = [];

  /// Alt gruplar dahil toplam kart sayısı.
  int get total => cards.length + children.fold<int>(0, (sum, c) => sum + c.total);
}

const noTopicTitle = 'Konu belirtilmemiş';

/// Kartları ağaç yapısında gruplar:
///  - Ders:  Ders › Konu › kartlar
///  - Kitap: Kitap (ya da bağımsız kaynak) › Konu › kartlar
///  - Konu:  Ana konu › alt konu › kartlar (MEB ağacının gerçek hiyerarşisi)
List<QuestionGroup> groupQuestions(
  List<QuestionCard> cards,
  GroupBy by, {
  required Map<String, CurriculumNode> curriculum,
  required Map<String, String> bookTitles,
  /// MEB konusu olmayan kartlar için konu: elle yazılan ya da otomatik
  /// ("Türev (otomatik)"). Yoksa "Konu belirtilmemiş".
  Map<String, String> fallbackTopics = const {},
}) {
  final top = <String, QuestionGroup>{};
  final sub = <String, QuestionGroup>{};

  QuestionGroup topGroup(String key, String title, {String? subtitle}) =>
      top.putIfAbsent(key, () => QuestionGroup(title: title, subtitle: subtitle));

  QuestionGroup subGroup(String topKey, QuestionGroup parent, String key, String title) =>
      sub.putIfAbsent('$topKey|$key', () {
        final group = QuestionGroup(title: title);
        parent.children.add(group);
        return group;
      });

  for (final card in cards) {
    final node = card.mebNodeId == null ? null : curriculum[card.mebNodeId];
    final fallback = node == null ? fallbackTopics[card.id] : null;
    final topicKey = node?.id ?? (fallback == null ? '-' : 'txt:${normalizeTr(fallback)}');
    final topicTitle = node?.title ?? fallback ?? noTopicTitle;
    switch (by) {
      case GroupBy.subject:
        final parent = topGroup(card.subject, card.subject);
        subGroup(card.subject, parent, topicKey, topicTitle).cards.add(card);
      case GroupBy.book:
        final bookTitle = card.bookId == null ? null : bookTitles[card.bookId];
        final key = card.bookId ?? 'src:${normalizeTr(card.sourceName)}';
        final parent = topGroup(key, bookTitle ?? card.sourceName);
        subGroup(key, parent, topicKey, topicTitle).cards.add(card);
      case GroupBy.topic:
        if (node == null) {
          topGroup(topicKey, topicTitle).cards.add(card);
        } else {
          final root = _rootOf(node, curriculum);
          final parent = topGroup(root.id, root.title, subtitle: root.subjectLabel);
          if (node.id == root.id) {
            parent.cards.add(card);
          } else {
            subGroup(root.id, parent, node.id, node.title).cards.add(card);
          }
        }
    }
  }

  final result = top.values.toList();
  _sortGroups(result);
  return result;
}

CurriculumNode _rootOf(CurriculumNode node, Map<String, CurriculumNode> curriculum) {
  var current = node;
  for (var i = 0; i < 10; i++) {
    final parent = current.parentId == null ? null : curriculum[current.parentId];
    if (parent == null) break;
    current = parent;
  }
  return current;
}

void _sortGroups(List<QuestionGroup> groups) {
  groups.sort((a, b) {
    // "Konu belirtilmemiş" her zaman en altta, diğerleri Türkçe alfabetik.
    if (a.title == noTopicTitle) return 1;
    if (b.title == noTopicTitle) return -1;
    return normalizeTr(a.title).compareTo(normalizeTr(b.title));
  });
  for (final g in groups) {
    _sortGroups(g.children);
  }
}
