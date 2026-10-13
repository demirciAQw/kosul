/// İçindekiler seviyesi. Şablon JSON'unda derinlikten türetilir.
enum NodeLevel {
  unit('Ünite'),
  topic('Konu'),
  subtopic('Alt konu');

  const NodeLevel(this.label);
  final String label;

  static NodeLevel fromDepth(int depth) => switch (depth) { 0 => unit, 1 => topic, _ => subtopic };
}

class ContentNode {
  const ContentNode({
    required this.id,
    required this.level,
    required this.title,
    this.pageStart,
    this.pageEnd,
    this.mebNodeId,
    this.mebMatchScore,
    this.questionCount,
    this.children = const [],
  });

  final String id;
  final NodeLevel level;
  final String title;
  final int? pageStart;
  final int? pageEnd;

  /// MEB kazanım ağacındaki karşılığı.
  final String? mebNodeId;

  /// Eşleştirme güveni (0–1). 1.0 = şablonda açıkça verilmiş ya da kullanıcı onaylamış.
  final double? mebMatchScore;

  /// Şablonda verilmişse testteki kesin soru sayısı ("Test 5: 20 soru").
  final int? questionCount;
  final List<ContentNode> children;

  bool get hasPages => pageStart != null && pageEnd != null;

  Iterable<ContentNode> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  ContentNode withMeb({
    required String? mebNodeId,
    required double? matchScore,
    required List<ContentNode> children,
  }) =>
      ContentNode(
        id: id,
        level: level,
        title: title,
        pageStart: pageStart,
        pageEnd: pageEnd,
        mebNodeId: mebNodeId,
        mebMatchScore: matchScore,
        questionCount: questionCount,
        children: children,
      );
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.examType,
    required this.subject,
    required this.pageCount,
    required this.avgQuestionsPerPage,
    required this.createdAt,
    this.publisher,
    this.templateAuthor,
    this.roots = const [],
  });

  final String id;
  final String title;
  final String? publisher;
  final String examType; // TYT | AYT | YDT
  final String subject;
  final int pageCount;
  final double avgQuestionsPerPage;
  final String? templateAuthor;
  final DateTime createdAt;
  final List<ContentNode> roots;

  Iterable<ContentNode> get allNodes sync* {
    for (final r in roots) {
      yield r;
      yield* r.descendants;
    }
  }

  int estimateQuestions(int pages) => (pages * avgQuestionsPerPage).round();

  Book copyWith({String? subject, List<ContentNode>? roots}) => Book(
        id: id,
        title: title,
        publisher: publisher,
        examType: examType,
        subject: subject ?? this.subject,
        pageCount: pageCount,
        avgQuestionsPerPage: avgQuestionsPerPage,
        templateAuthor: templateAuthor,
        createdAt: createdAt,
        roots: roots ?? this.roots,
      );
}

abstract interface class LibraryRepository {
  Stream<List<Book>> watchLibrary();
  Future<Book?> findById(String id);

  /// Kitabı ve tüm ağacını atomik olarak yazar (upsert; mevcut düğüm
  /// kimlikleri korunur, böylece oturum/kart referansları kopmaz).
  Future<void> save(Book book);
  Future<void> rename(String bookId, {required String title, String? publisher});
  Future<void> delete(String bookId);
}

class BookTemplateException implements Exception {
  const BookTemplateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Taşınabilir şablon biçimi (domain yalnızca sözleşmeyi bilir; JSON data katmanında).
abstract interface class BookTemplateCodec {
  /// Hatalı içerikte [BookTemplateException] fırlatır.
  Book decode(String raw);
  String encode(Book book);
}
