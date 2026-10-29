import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/ink.dart';
import '../domain/pdf_models.dart';

/// PDF kitapları, PDF'ten seçilen soruların yeri ve kalem katmanları.
class PdfRepository {
  PdfRepository(this._db);
  final AppDatabase _db;

  // ── Kitaplar ──
  PdfBook _book(PdfDocumentRow r) => PdfBook(
        id: r.id,
        title: r.title,
        filePath: r.filePath,
        pageCount: r.pageCount,
        subject: r.subject,
        lastPage: r.lastPage,
        createdAt: r.createdAt,
      );

  Stream<List<PdfBook>> watchBooks() =>
      (_db.select(_db.pdfDocuments)..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
          .watch()
          .map((rows) => [for (final r in rows) _book(r)]);

  Future<PdfBook?> book(String id) async {
    final r = await (_db.select(_db.pdfDocuments)..where((d) => d.id.equals(id))).getSingleOrNull();
    return r == null ? null : _book(r);
  }

  Future<void> addBook(PdfBook b) => _db.into(_db.pdfDocuments).insert(PdfDocumentsCompanion.insert(
        id: b.id,
        title: b.title,
        filePath: b.filePath,
        pageCount: b.pageCount,
        subject: Value(b.subject),
        createdAt: b.createdAt,
      ));

  Future<void> setLastPage(String id, int page) => (_db.update(_db.pdfDocuments)..where((d) => d.id.equals(id)))
      .write(PdfDocumentsCompanion(lastPage: Value(page)));

  Future<void> setSubject(String id, String subject) =>
      (_db.update(_db.pdfDocuments)..where((d) => d.id.equals(id)))
          .write(PdfDocumentsCompanion(subject: Value(subject)));

  // ── Soru yerleri ──
  PdfQuestionRef _ref(PdfQuestionRefRow r) => PdfQuestionRef(
        cardId: r.cardId,
        documentId: r.documentId,
        page: r.page,
        x0: r.x0,
        y0: r.y0,
        x1: r.x1,
        y1: r.y1,
      );

  Stream<Map<String, PdfQuestionRef>> watchRefs() =>
      _db.select(_db.pdfQuestionRefs).watch().map((rows) => {for (final r in rows) r.cardId: _ref(r)});

  Future<void> saveRef(PdfQuestionRef r) => _db.into(_db.pdfQuestionRefs).insertOnConflictUpdate(
        PdfQuestionRefsCompanion.insert(
          cardId: r.cardId,
          documentId: r.documentId,
          page: r.page,
          x0: r.x0,
          y0: r.y0,
          x1: r.x1,
          y1: r.y1,
        ),
      );

  // ── Kalem katmanları ──
  InkLayer _layer(InkLayerRow r) => InkLayer(
        id: r.id,
        ownerType: r.ownerType,
        ownerId: r.ownerId,
        name: r.name,
        strokes: decodeStrokes(r.strokesJson),
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );

  Stream<List<InkLayer>> watchLayers(String ownerType, String ownerId) => (_db.select(_db.inkLayers)
        ..where((l) => l.ownerType.equals(ownerType) & l.ownerId.equals(ownerId))
        ..orderBy([(l) => OrderingTerm.asc(l.createdAt)]))
      .watch()
      .map((rows) => [for (final r in rows) _layer(r)]);

  Future<List<InkLayer>> layers(String ownerType, String ownerId) => (_db.select(_db.inkLayers)
        ..where((l) => l.ownerType.equals(ownerType) & l.ownerId.equals(ownerId))
        ..orderBy([(l) => OrderingTerm.asc(l.createdAt)]))
      .get()
      .then((rows) => [for (final r in rows) _layer(r)]);

  Future<void> saveLayer(InkLayer l) => _db.into(_db.inkLayers).insertOnConflictUpdate(InkLayersCompanion.insert(
        id: l.id,
        ownerType: l.ownerType,
        ownerId: l.ownerId,
        name: l.name,
        strokesJson: encodeStrokes(l.strokes),
        createdAt: l.createdAt,
        updatedAt: l.updatedAt,
      ));

  Future<void> deleteLayer(String id) => (_db.delete(_db.inkLayers)..where((l) => l.id.equals(id))).go();

  /// Kart → kayıtlı çözüm katmanı sayısı (Eksikler'de "çözüm var" sayılır).
  Stream<Map<String, int>> watchCardLayerCounts() =>
      (_db.select(_db.inkLayers)..where((l) => l.ownerType.equals('card'))).watch().map((rows) {
        final out = <String, int>{};
        for (final r in rows) {
          out[r.ownerId] = (out[r.ownerId] ?? 0) + 1;
        }
        return out;
      });
}
