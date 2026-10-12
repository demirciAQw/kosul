import '../../../../core/json/json_reader.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../curriculum/domain/curriculum.dart';
import '../../domain/library.dart';

/// Topluluk tarafından paylaşılan kitap şablonunun taşınabilir JSON sözleşmesi.
///
/// ```json
/// {
///   "format": "kocum.book-template", "schemaVersion": 1, "author": "...",
///   "book": { "title", "publisher", "examType", "subject", "pageCount", "avgQuestionsPerPage" },
///   "units": [ { "title", "pageStart", "pageEnd", "meb", "children": [ ... ] } ]
/// }
/// ```
/// Yerel kimlikler (UUID) ASLA dışa aktarılmaz; içe aktarırken yenileri üretilir.
class BookTemplateModel {
  const BookTemplateModel({
    required this.title,
    required this.examType,
    required this.subject,
    required this.pageCount,
    required this.avgQuestionsPerPage,
    required this.units,
    this.publisher,
    this.author,
  });

  static const format = 'kocum.book-template';
  static const currentSchemaVersion = 1;
  static const maxDepth = 3; // Ünite › Konu › Alt konu
  static const maxNodes = 5000; // kötü niyetli/bozuk dev dosyalara karşı
  static const examTypes = {'TYT', 'AYT', 'YDT'};

  final String title;
  final String? publisher;
  final String examType;
  final String subject;
  final int pageCount;
  final double avgQuestionsPerPage;
  final String? author;
  final List<TemplateNodeModel> units;

  factory BookTemplateModel.fromJson(Map<String, dynamic> json) {
    final r = JsonReader(json);
    final fmt = r.optString('format');
    if (fmt != null && fmt != format) {
      throw JsonFormatException(r.at('format'), 'Bu dosya bir Koçum kitap şablonu değil');
    }
    final version = r.requireInt('schemaVersion', min: 1);
    if (version > currentSchemaVersion) {
      throw JsonFormatException(r.at('schemaVersion'),
          'Şablon daha yeni bir uygulama sürümüyle hazırlanmış (v$version). Uygulamayı güncelle');
    }

    final b = r.requireObject('book');
    final examType = b.requireString('examType').toUpperCase();
    if (!examTypes.contains(examType)) {
      throw JsonFormatException(b.at('examType'), 'TYT, AYT veya YDT olmalı');
    }
    final pageCount = b.requireInt('pageCount', min: 1, max: 5000);
    final counter = _Counter();

    return BookTemplateModel(
      title: b.requireString('title', maxLength: 200),
      publisher: b.optString('publisher', maxLength: 120),
      examType: examType,
      subject: b.requireString('subject', maxLength: 80),
      pageCount: pageCount,
      avgQuestionsPerPage: b.requireDouble('avgQuestionsPerPage', min: 0, max: 100),
      author: r.optString('author', maxLength: 80),
      units: [
        for (final u in r.objectList('units', required: true))
          TemplateNodeModel._parse(u, depth: 0, pageCount: pageCount, counter: counter),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'format': format,
        'schemaVersion': currentSchemaVersion,
        if (author != null) 'author': author,
        'book': {
          'title': title,
          if (publisher != null) 'publisher': publisher,
          'examType': examType,
          'subject': subject,
          'pageCount': pageCount,
          'avgQuestionsPerPage': avgQuestionsPerPage,
        },
        'units': [for (final u in units) u.toJson()],
      };

  Book toEntity({required IdGenerator ids, required DateTime now}) => Book(
        id: ids.next(),
        title: title,
        publisher: publisher,
        examType: examType,
        subject: subject,
        pageCount: pageCount,
        avgQuestionsPerPage: avgQuestionsPerPage,
        templateAuthor: author,
        createdAt: now,
        roots: [for (final u in units) u.toEntity(ids, depth: 0)],
      );

  factory BookTemplateModel.fromEntity(Book book) => BookTemplateModel(
        title: book.title,
        publisher: book.publisher,
        examType: book.examType,
        subject: book.subject,
        pageCount: book.pageCount,
        avgQuestionsPerPage: book.avgQuestionsPerPage,
        author: book.templateAuthor,
        units: [for (final n in book.roots) TemplateNodeModel.fromEntity(n)],
      );
}

class TemplateNodeModel {
  const TemplateNodeModel({
    required this.title,
    this.pageStart,
    this.pageEnd,
    this.mebCode,
    this.questions,
    this.children = const [],
  });

  final String title;
  final int? pageStart;
  final int? pageEnd;

  /// İsteğe bağlı açık MEB kimliği; varsa otomatik eşleştirmeyi geçersiz kılar.
  final String? mebCode;

  /// İsteğe bağlı: testteki kesin soru sayısı (JSON'da "questions").
  /// Eski uygulama sürümleri bu alanı yok sayar; şema sürümü değişmez.
  final int? questions;
  final List<TemplateNodeModel> children;

  /// Bağımsız kullanım için (ör. tek bir üniteyi yapıştırma).
  factory TemplateNodeModel.fromJson(Map<String, dynamic> json, {int depth = 0, int pageCount = 5000}) =>
      TemplateNodeModel._parse(JsonReader(json), depth: depth, pageCount: pageCount, counter: _Counter());

  factory TemplateNodeModel._parse(
    JsonReader r, {
    required int depth,
    required int pageCount,
    required _Counter counter,
  }) {
    if (++counter.value > BookTemplateModel.maxNodes) {
      throw JsonFormatException(r.path, 'Şablon çok büyük (en fazla ${BookTemplateModel.maxNodes} başlık)');
    }
    final start = r.optInt('pageStart', min: 1, max: pageCount);
    final end = r.optInt('pageEnd', min: 1, max: pageCount);
    if ((start == null) != (end == null)) {
      throw JsonFormatException(r.path, 'pageStart ve pageEnd birlikte verilmeli');
    }
    if (start != null && end! < start) {
      throw JsonFormatException(r.at('pageEnd'), "pageEnd, pageStart'tan küçük olamaz");
    }
    final children = r.objectList('children');
    if (children.isNotEmpty && depth + 1 >= BookTemplateModel.maxDepth) {
      throw JsonFormatException(r.at('children'), 'En fazla 3 seviye desteklenir (Ünite › Konu › Alt konu)');
    }
    return TemplateNodeModel(
      title: r.requireString('title', maxLength: 200),
      pageStart: start,
      pageEnd: end,
      mebCode: r.optString('meb', maxLength: 120),
      questions: r.optInt('questions', min: 1, max: 500),
      children: [
        for (final c in children)
          TemplateNodeModel._parse(c, depth: depth + 1, pageCount: pageCount, counter: counter),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        if (pageStart != null) 'pageStart': pageStart,
        if (pageEnd != null) 'pageEnd': pageEnd,
        if (mebCode != null) 'meb': mebCode,
        if (questions != null) 'questions': questions,
        if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
      };

  ContentNode toEntity(IdGenerator ids, {required int depth}) => ContentNode(
        id: ids.next(),
        level: NodeLevel.fromDepth(depth),
        title: title,
        pageStart: pageStart,
        pageEnd: pageEnd,
        mebNodeId: mebCode,
        questionCount: questions,
        children: [for (final c in children) c.toEntity(ids, depth: depth + 1)],
      );

  /// Yalnızca güvenilir eşleşmeler paylaşılır: topluluk şablonları
  /// zamanla "önceden normalize edilmiş" hâle gelir.
  factory TemplateNodeModel.fromEntity(ContentNode n) => TemplateNodeModel(
        title: n.title,
        pageStart: n.pageStart,
        pageEnd: n.pageEnd,
        mebCode: (n.mebMatchScore ?? 0) >= TopicMatcher.autoAcceptThreshold ? n.mebNodeId : null,
        questions: n.questionCount,
        children: [for (final c in n.children) TemplateNodeModel.fromEntity(c)],
      );
}

class _Counter {
  int value = 0;
}
