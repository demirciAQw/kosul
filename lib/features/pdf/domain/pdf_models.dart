import 'ink.dart';

/// Uygulamaya eklenmiş PDF kitap.
class PdfBook {
  const PdfBook({
    required this.id,
    required this.title,
    required this.filePath,
    required this.pageCount,
    required this.createdAt,
    this.subject,
    this.lastPage = 0,
  });
  final String id;
  final String title;
  final String filePath; // medya köküne göre göreli
  final int pageCount;
  final String? subject; // "TYT Fizik"; ilk kayıtta bir kez seçilir
  final int lastPage; // 0'dan
  final DateTime createdAt;
}

/// PDF'ten seçilmiş sorunun yeri: sayfa ve sayfaya oranla dikdörtgen (0–1).
class PdfQuestionRef {
  const PdfQuestionRef({
    required this.cardId,
    required this.documentId,
    required this.page,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });
  final String cardId;
  final String documentId;
  final int page;
  final double x0, y0, x1, y1;

  /// Genişlik / yükseklik oranı için sayfanın en/boy oranıyla çarpılır.
  double aspect(double pageWidth, double pageHeight) =>
      ((x1 - x0) * pageWidth) / ((y1 - y0) * pageHeight);
}

/// Kalem katmanı: bir PDF sayfasının çalışma çizgileri ya da bir sorunun
/// kayıtlı çözümlerinden biri.
class InkLayer {
  const InkLayer({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.name,
    required this.strokes,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String ownerType; // page | card
  final String ownerId;
  final String name;
  final List<InkStroke> strokes;
  final DateTime createdAt;
  final DateTime updatedAt;

  static String pageOwner(String documentId, int page) => '$documentId:$page';
}
