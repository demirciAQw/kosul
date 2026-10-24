import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../core/media/media_storage.dart';
import '../domain/question_card.dart';

/// PDF'e girecek bir soru: kart ve kutunun başlığı (ders, konu, kaynak…).
class PdfQuestion {
  const PdfQuestion(this.card, this.header);
  final QuestionCard card;
  final String header;
}

/// 2×2 ızgarada kutuların yeri (A4, nokta). Saf hesap: test edilebilir.
List<Rect> gridCells(Size client, {double top = 30, double bottom = 18, double gap = 10}) {
  final w = (client.width - gap) / 2;
  final h = (client.height - top - bottom - gap) / 2;
  return [
    for (var row = 0; row < 2; row++)
      for (var col = 0; col < 2; col++) Rect.fromLTWH(col * (w + gap), top + row * (h + gap), w, h),
  ];
}

/// Görüntüyü kutuya oranını bozmadan, ortalayarak sığdırır.
Rect fitInto(Rect box, double imageWidth, double imageHeight) {
  if (imageWidth <= 0 || imageHeight <= 0) return box;
  final scale = [box.width / imageWidth, box.height / imageHeight].reduce((a, b) => a < b ? a : b);
  final w = imageWidth * scale, h = imageHeight * scale;
  return Rect.fromLTWH(box.left + (box.width - w) / 2, box.top + (box.height - h) / 2, w, h);
}

/// Sorular sayfada 4'er (2×2), fotoğraflarıyla; isteğe bağlı cevap anahtarı.
/// Fotoğraflar WebP saklandığı için PDF'e girmeden JPEG'e çevrilir.
Future<Uint8List> buildQuestionPdf({
  required String title,
  required List<PdfQuestion> items,
  required MediaStorage media,
  bool answerKey = true,
  String? subtitle,
}) async {
  final regular = (await rootBundle.load('assets/fonts/NotoSans-Regular.ttf')).buffer.asUint8List();
  final boldData = (await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')).buffer.asUint8List();
  final titleFont = PdfTrueTypeFont(boldData, 12);
  final headFont = PdfTrueTypeFont(boldData, 8.5);
  final textFont = PdfTrueTypeFont(regular, 8.5);
  final smallFont = PdfTrueTypeFont(regular, 7.5);
  final grey = PdfSolidBrush(PdfColor(95, 99, 104));
  final border = PdfPen(PdfColor(218, 220, 224), width: 0.8);
  final wrap = PdfStringFormat(wordWrap: PdfWordWrapType.word, lineSpacing: 1);

  final doc = PdfDocument();
  doc.pageSettings.margins.all = 28;
  try {
    final pageCount = (items.length / 4).ceil();
    for (var p = 0; p < pageCount; p++) {
      final page = doc.pages.add();
      final g = page.graphics;
      final size = page.getClientSize();
      g.drawString(title, titleFont, bounds: Rect.fromLTWH(0, 0, size.width * 0.7, 18));
      if (subtitle != null) {
        g.drawString(subtitle, smallFont,
            brush: grey,
            bounds: Rect.fromLTWH(size.width * 0.7, 3, size.width * 0.3, 14),
            format: PdfStringFormat(alignment: PdfTextAlignment.right));
      }
      g.drawString('${p + 1} / $pageCount', smallFont,
          brush: grey,
          bounds: Rect.fromLTWH(0, size.height - 12, size.width, 12),
          format: PdfStringFormat(alignment: PdfTextAlignment.center));

      final cells = gridCells(size);
      for (var k = 0; k < 4; k++) {
        final index = p * 4 + k;
        if (index >= items.length) break;
        final item = items[index];
        final cell = cells[k];
        g.drawRectangle(pen: border, bounds: cell);
        final inner = Rect.fromLTWH(cell.left + 8, cell.top + 6, cell.width - 16, cell.height - 12);
        g.drawString('${index + 1}.', headFont, bounds: Rect.fromLTWH(inner.left, inner.top, 22, 14));
        g.drawString(item.header, textFont,
            brush: grey, bounds: Rect.fromLTWH(inner.left + 22, inner.top, inner.width - 22, 26), format: wrap);
        final imageBox = Rect.fromLTWH(inner.left, inner.top + 30, inner.width, inner.height - 30);
        final bitmap = await _bitmapOf(media, item.card.questionImage);
        if (bitmap != null) {
          g.drawImage(bitmap, fitInto(imageBox, bitmap.width.toDouble(), bitmap.height.toDouble()));
        } else {
          g.drawString('Fotoğrafı yok. ${item.card.locationText}', textFont,
              brush: grey, bounds: imageBox, format: wrap);
        }
      }
    }

    if (answerKey && items.isNotEmpty) {
      var page = doc.pages.add();
      var size = page.getClientSize();
      page.graphics.drawString('Cevap anahtarı', titleFont, bounds: Rect.fromLTWH(0, 0, size.width, 18));
      var y = 28.0;
      for (final (i, item) in items.indexed) {
        if (y > size.height - 20) {
          page = doc.pages.add();
          size = page.getClientSize();
          y = 0;
        }
        final answer = item.card.correctAnswer ?? '—';
        page.graphics.drawString('${i + 1})  $answer', headFont, bounds: Rect.fromLTWH(0, y, 120, 14));
        page.graphics.drawString(item.header, smallFont,
            brush: grey, bounds: Rect.fromLTWH(120, y + 1, size.width - 120, 14));
        y += 15;
      }
    }
    return Uint8List.fromList(await doc.save());
  } finally {
    doc.dispose();
  }
}

/// Medyadaki fotoğrafı PDF'in okuyabileceği JPEG'e çevirir; yoksa ya da
/// çevrilemezse null.
Future<PdfBitmap?> _bitmapOf(MediaStorage media, String? path) async {
  if (path == null) return null;
  try {
    final file = media.resolve(path);
    if (!await file.exists()) return null;
    final jpeg = await FlutterImageCompress.compressWithList(
      await file.readAsBytes(),
      minWidth: 1100,
      minHeight: 1100,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    return PdfBitmap(jpeg);
  } catch (_) {
    return null;
  }
}
