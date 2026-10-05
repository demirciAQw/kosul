import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/json/json_reader.dart';
import '../../../core/text/turkish_text.dart';
import '../../../core/utils/enum_x.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/library.dart';
import 'models/book_template_model.dart';

class JsonBookTemplateCodec implements BookTemplateCodec {
  JsonBookTemplateCodec({required IdGenerator ids, required Clock clock})
      : _ids = ids,
        _clock = clock;

  final IdGenerator _ids;
  final Clock _clock;

  @override
  Book decode(String raw) {
    // Windows Not Defteri'nin eklediği BOM jsonDecode'u bozar.
    final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw BookTemplateException('JSON sözdizimi hatalı: ${e.message}');
    }
    try {
      final root = JsonReader.root(decoded);
      return BookTemplateModel.fromJson(root.raw).toEntity(ids: _ids, now: _clock());
    } on JsonFormatException catch (e) {
      throw BookTemplateException(e.toString());
    }
  }

  @override
  String encode(Book book) =>
      const JsonEncoder.withIndent('  ').convert(BookTemplateModel.fromEntity(book).toJson());
}

class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<List<Book>> watchLibrary() {
    // Tek LEFT JOIN: hem kitap hem düğüm tablosundaki her değişiklikte yeniden yayınlar.
    final query = _db.select(_db.books).join([
      leftOuterJoin(_db.contentNodes, _db.contentNodes.bookId.equalsExp(_db.books.id)),
    ])
      ..orderBy([OrderingTerm.asc(_db.books.title), OrderingTerm.asc(_db.contentNodes.sortOrder)]);

    return query.watch().map((rows) {
      final books = <String, BookRow>{};
      final nodes = <String, List<ContentNodeRow>>{};
      for (final row in rows) {
        final b = row.readTable(_db.books);
        books[b.id] = b;
        final n = row.readTableOrNull(_db.contentNodes);
        if (n != null) (nodes[b.id] ??= []).add(n);
      }
      return [for (final b in books.values) _toEntity(b, nodes[b.id] ?? const [])];
    });
  }

  @override
  Future<Book?> findById(String id) async {
    final row = await (_db.select(_db.books)..where((b) => b.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final nodes = await (_db.select(_db.contentNodes)..where((n) => n.bookId.equals(id))).get();
    return _toEntity(row, nodes);
  }

  @override
  Future<void> save(Book book) => _db.transaction(() async {
        await _db.into(_db.books).insertOnConflictUpdate(BooksCompanion.insert(
              id: book.id,
              title: book.title,
              publisher: Value(book.publisher),
              examType: book.examType,
              subject: book.subject,
              pageCount: book.pageCount,
              avgQuestionsPerPage: book.avgQuestionsPerPage,
              templateAuthor: Value(book.templateAuthor),
              createdAt: book.createdAt,
            ));
        final rows = _flatten(book);
        await _db.batch((b) => b.insertAllOnConflictUpdate(_db.contentNodes, rows));
        final keep = [for (final r in rows) r.id.value];
        await (_db.delete(_db.contentNodes)
              ..where((n) => n.bookId.equals(book.id) & n.id.isNotIn(keep)))
            .go();
      });

  @override
  Future<void> delete(String bookId) =>
      (_db.delete(_db.books)..where((b) => b.id.equals(bookId))).go();

  List<ContentNodesCompanion> _flatten(Book book) {
    final out = <ContentNodesCompanion>[];
    void walk(List<ContentNode> nodes, String? parentId) {
      for (var i = 0; i < nodes.length; i++) {
        final n = nodes[i];
        out.add(ContentNodesCompanion.insert(
          id: n.id,
          bookId: book.id,
          parentId: Value(parentId),
          level: n.level.name,
          title: n.title,
          pageStart: Value(n.pageStart),
          pageEnd: Value(n.pageEnd),
          sortOrder: i,
          mebNodeId: Value(n.mebNodeId),
          mebMatchScore: Value(n.mebMatchScore),
        ));
        walk(n.children, n.id);
      }
    }

    walk(book.roots, null);
    return out;
  }

  static Book _toEntity(BookRow b, List<ContentNodeRow> rows) {
    final byParent = <String?, List<ContentNodeRow>>{};
    for (final r in rows) {
      (byParent[r.parentId] ??= []).add(r);
    }
    for (final list in byParent.values) {
      list.sort((a, c) => a.sortOrder.compareTo(c.sortOrder));
    }
    List<ContentNode> build(String? parentId) => [
          for (final r in byParent[parentId] ?? const <ContentNodeRow>[])
            ContentNode(
              id: r.id,
              level: NodeLevel.values.byNameOr(r.level, NodeLevel.topic),
              title: r.title,
              pageStart: r.pageStart,
              pageEnd: r.pageEnd,
              mebNodeId: r.mebNodeId,
              mebMatchScore: r.mebMatchScore,
              children: build(r.id),
            ),
        ];

    return Book(
      id: b.id,
      title: b.title,
      publisher: b.publisher,
      examType: b.examType,
      subject: b.subject,
      pageCount: b.pageCount,
      avgQuestionsPerPage: b.avgQuestionsPerPage,
      templateAuthor: b.templateAuthor,
      createdAt: b.createdAt,
      roots: build(null),
    );
  }
}

/// Dosya seçme / paylaşma (platform G/Ç'si).
class TemplateFileGateway {
  const TemplateFileGateway();
  static const maxBytes = 2 * 1024 * 1024;

  Future<String?> pickTemplateJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    final file = File(path);
    if (await file.length() > maxBytes) {
      throw const BookTemplateException('Dosya çok büyük (en fazla 2 MB).');
    }
    return file.readAsString();
  }

  /// Telegram/WhatsApp/Drive'a doğrudan paylaşım: topluluk gücü.
  Future<void> share({required String fileName, required String json}) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(json, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      title: fileName,
    ));
  }

  /// "345 TYT Matematik Soru Bankası" → "345_tyt_matematik_soru_bankasi.json"
  static String fileNameFor(Book book) {
    final slug = normalizeTr(book.title).replaceAll(' ', '_');
    return '${slug.isEmpty ? 'kitap' : slug}.json';
  }
}
