import '../../../core/text/turkish_text.dart';
import '../../curriculum/domain/curriculum.dart';
import 'library.dart';

class ImportReport {
  const ImportReport({
    required this.book,
    required this.matched,
    required this.needsReview,
    required this.unmatched,
  });
  final Book book;
  final int matched;
  final int needsReview;
  final int unmatched;
}

/// JSON → doğrula → MEB ağacına normalize et → kaydet.
class ImportBookTemplate {
  ImportBookTemplate({
    required BookTemplateCodec codec,
    required CurriculumRepository curriculum,
    required LibraryRepository library,
  })  : _codec = codec,
        _curriculum = curriculum,
        _library = library;

  final BookTemplateCodec _codec;
  final CurriculumRepository _curriculum;
  final LibraryRepository _library;

  Future<ImportReport> call(String rawJson) async {
    final decoded = _codec.decode(rawJson);
    final subjectNorm = normalizeTr(decoded.subject);
    final candidates = [
      for (final n in await _curriculum.all())
        if (n.examType == decoded.examType && normalizeTr(n.subject) == subjectNorm) n,
    ];
    final validIds = {for (final c in candidates) c.id};
    final matcher = TopicMatcher(candidates);
    var matched = 0, needsReview = 0, unmatched = 0;

    ContentNode normalize(ContentNode node, String? parentMeb) {
      String? mebId;
      double? score;
      if (node.mebNodeId != null && validIds.contains(node.mebNodeId)) {
        mebId = node.mebNodeId; // şablon yazarı açıkça vermiş
        score = 1.0;
      } else {
        final m = matcher.match(node.title, parentMebId: parentMeb);
        mebId = m?.nodeId;
        score = m?.score;
      }
      if (mebId == null) {
        unmatched++;
      } else if (score! >= TopicMatcher.autoAcceptThreshold) {
        matched++;
      } else {
        needsReview++;
      }
      return node.withMeb(
        mebNodeId: mebId,
        matchScore: score,
        children: [for (final c in node.children) normalize(c, mebId ?? parentMeb)],
      );
    }

    final book = decoded.copyWith(
      // "matematik" → "Matematik": ders adını müfredattaki yazımla hizala.
      subject: candidates.isEmpty ? null : candidates.first.subject,
      roots: [for (final r in decoded.roots) normalize(r, null)],
    );
    await _library.save(book);
    return ImportReport(book: book, matched: matched, needsReview: needsReview, unmatched: unmatched);
  }
}

class ExportBookTemplate {
  ExportBookTemplate({required BookTemplateCodec codec, required LibraryRepository library})
      : _codec = codec,
        _library = library;

  final BookTemplateCodec _codec;
  final LibraryRepository _library;

  Future<String> call(String bookId) async {
    final book = await _library.findById(bookId);
    if (book == null) throw const BookTemplateException('Kitap bulunamadı.');
    return _codec.encode(book);
  }
}
