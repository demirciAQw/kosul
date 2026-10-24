import 'dart:convert';

import '../../../core/text/turkish_text.dart';
import '../../library/domain/library.dart';
import 'planning.dart';

/// Yapay zekânın (Claude vb.) hazırladığı çalışma programının biçimi.
///
/// ```json
/// {
///   "format": "kocum.plan", "version": 1,
///   "title": "26 Ekim haftası", "startsOn": "2026-10-26", "endsOn": "2026-11-01",
///   "tasks": [
///     {"date": "2026-10-26", "time": "19:00", "minutes": 40, "title": "Üstel fonksiyonlar tekrar",
///      "subject": "AYT Matematik", "book": "MEB 11. Sınıf Matematik",
///      "section": "4.1 Üstel Fonksiyonlar ve Nitel Özellikleri", "pages": "248-266", "questions": 20}
///   ]
/// }
/// ```
const planJsonSchema = '''{
  "format": "kocum.plan",
  "version": 1,
  "title": "kısa ad",
  "startsOn": "YYYY-AA-GG",
  "endsOn": "YYYY-AA-GG",
  "tasks": [
    {
      "date": "YYYY-AA-GG",
      "time": "SS:DD (isteğe bağlı)",
      "minutes": 40,
      "title": "ne yapılacak (kısa)",
      "subject": "ders, ör. AYT Matematik",
      "book": "kaynağın adı, listedeki gibi (isteğe bağlı)",
      "section": "kitaptaki bölüm ya da test adı, listedeki gibi (isteğe bağlı)",
      "pages": "248-266 (isteğe bağlı)",
      "questions": 20
    }
  ]
}''';

class PlanImportException implements Exception {
  const PlanImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PlanImport {
  const PlanImport({required this.draft, required this.warnings, required this.matchedBooks});
  final NewPlanDraft draft;

  /// Atlanan görevler, eşleşmeyen kitaplar…
  final List<String> warnings;
  final int matchedBooks;
}

const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
String _two(int n) => n.toString().padLeft(2, '0');

DateTime? _date(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(v.trim());
  if (m == null) return null;
  final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return d.month == int.parse(m[2]!) ? d : null; // 31 Şubat gibi tarihleri ele
}

int? _int(Object? v) => v is int ? v : (v is num ? v.round() : (v is String ? int.tryParse(v.trim()) : null));

String? _str(Object? v, {int max = 200}) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  return t.length > max ? '${t.substring(0, max)}…' : t;
}

/// Yapıştırılan metinden (```json bloğu ya da düz JSON) programı okur; kitap
/// ve bölüm adlarını kitaplığa eşler. Hiçbir şey kaydetmez.
PlanImport parsePlanJson(String text, {required List<Book> books, required DateTime today}) {
  final start = text.indexOf('{'), end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const PlanImportException('Metinde JSON bulunamadı. Yapay zekânın verdiği JSON bloğunu olduğu gibi yapıştır.');
  }
  final Object? root;
  try {
    root = jsonDecode(text.substring(start, end + 1));
  } on FormatException catch (e) {
    throw PlanImportException('JSON okunamadı: ${e.message}');
  }
  if (root is! Map<String, dynamic>) throw const PlanImportException('Beklenen biçim bir JSON nesnesi.');
  final warnings = <String>[];
  if (root['format'] != 'kocum.plan') warnings.add('"format": "kocum.plan" yok; yine de okunmaya çalışıldı.');
  final rawTasks = root['tasks'];
  if (rawTasks is! List || rawTasks.isEmpty) throw const PlanImportException('Programda görev ("tasks") yok.');
  if (rawTasks.length > 300) throw const PlanImportException('Programda en fazla 300 görev olabilir.');

  final byTitle = {for (final b in books) normalizeTr(b.title): b};
  Book? matchBook(String? name) {
    if (name == null) return null;
    final n = normalizeTr(name);
    return byTitle[n] ?? books.where((b) => normalizeTr(b.title).contains(n) || n.contains(normalizeTr(b.title))).firstOrNull;
  }

  ContentNode? matchNode(Book book, String? section) {
    if (section == null) return null;
    final n = normalizeTr(section);
    ContentNode? contains;
    ContentNode? search(List<ContentNode> nodes) {
      for (final node in nodes) {
        final t = normalizeTr(node.title);
        if (t == n) return node;
        if (contains == null && (t.contains(n) || n.contains(t)) && t.length > 3) contains = node;
        final found = search(node.children);
        if (found != null) return found;
      }
      return null;
    }

    return search(book.roots) ?? contains;
  }

  final entries = <(DateTime?, String, NewPlanTaskDraft)>[];
  final unmatched = <String>{};
  var matched = 0;
  for (final (i, raw) in rawTasks.indexed) {
    if (raw is! Map) {
      warnings.add('${i + 1}. görev okunamadı, atlandı.');
      continue;
    }
    final title = _str(raw['title']);
    if (title == null) {
      warnings.add('${i + 1}. görevin başlığı yok, atlandı.');
      continue;
    }
    final date = _date(raw['date']);
    final time = _str(raw['time'], max: 5);
    final minutes = _int(raw['minutes']);
    final questions = _int(raw['questions']);
    final bookName = _str(raw['book']);
    final section = _str(raw['section']);
    final pages = _str(raw['pages'], max: 20);
    final book = matchBook(bookName);
    if (bookName != null && book == null) unmatched.add(bookName);
    if (book != null) matched++;
    final node = book == null ? null : matchNode(book, section);

    final when = date == null
        ? ''
        : '${_weekdays[date.weekday - 1]} ${_two(date.day)}.${_two(date.month)}${time == null ? '' : ' $time'} · ';
    final details = [
      if (book != null) book.title else if (bookName != null) bookName,
      if (node != null) node.title else if (section != null) section,
      if (pages != null) 's. $pages',
      if (minutes != null && minutes > 0) '$minutes dk',
    ].join(', ');
    entries.add((
      date,
      '${time ?? ''}${i.toString().padLeft(4, '0')}',
      NewPlanTaskDraft(
        title: '$when$title${details.isEmpty ? '' : ' ($details)'}',
        bookId: book?.id,
        contentNodeId: node?.id,
        targetQuestions: questions != null && questions > 0 ? questions : null,
      ),
    ));
  }
  if (entries.isEmpty) throw const PlanImportException('Geçerli görev kalmadı.');
  for (final name in unmatched) {
    warnings.add('"$name" kitaplığında bulunamadı; görev kitapsız eklendi.');
  }

  // Tarih ve saate göre sırala; tarihsizler sonda, kendi sıralarıyla.
  entries.sort((a, b) {
    final da = a.$1, db = b.$1;
    if (da == null && db == null) return a.$2.compareTo(b.$2);
    if (da == null) return 1;
    if (db == null) return -1;
    final c = da.compareTo(db);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  final dates = [for (final e in entries) if (e.$1 != null) e.$1!];
  final day = DateTime(today.year, today.month, today.day);
  final startsOn = _date(root['startsOn']) ?? (dates.isEmpty ? day : dates.first);
  var endsOn = _date(root['endsOn']) ?? (dates.isEmpty ? day.add(const Duration(days: 6)) : dates.last);
  if (endsOn.isBefore(startsOn)) endsOn = startsOn;

  return PlanImport(
    draft: NewPlanDraft(
      title: _str(root['title'], max: 80) ?? 'Yapay zekâ programı',
      startsOn: startsOn,
      endsOn: endsOn,
      tasks: [for (final e in entries) e.$3],
    ),
    warnings: warnings,
    matchedBooks: matched,
  );
}
