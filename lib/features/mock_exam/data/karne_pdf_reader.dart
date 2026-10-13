import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../domain/karne_parser.dart';

/// Seçilen karne dosyası.
class KarneFile {
  const KarneFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Karne PDF'lerini seçer (birden çok dosya olabilir). Vazgeçilirse boş liste.
Future<List<KarneFile>> pickKarneFiles() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return const [];
  return [
    for (final f in result.files)
      if (f.bytes != null) KarneFile(f.name, f.bytes!),
  ];
}

/// PDF'teki kelimeleri sayfa sayfa, konumlarıyla okur. Arayüz donmasın diye
/// arka planda çalıştırılır.
Future<List<List<PdfWord>>> readKarneWords(Uint8List bytes) => compute(_readWords, bytes);

List<List<PdfWord>> _readWords(Uint8List bytes) {
  final document = sf.PdfDocument(inputBytes: bytes);
  try {
    final extractor = sf.PdfTextExtractor(document);
    final pages = <List<PdfWord>>[];
    for (var i = 0; i < document.pages.count; i++) {
      final words = <PdfWord>[];
      for (final line in extractor.extractTextLines(startPageIndex: i, endPageIndex: i)) {
        for (final word in line.wordCollection) {
          words.addAll(_split(word.text, word.bounds));
        }
      }
      pages.add(words);
    }
    return pages;
  } finally {
    document.dispose();
  }
}

/// Bir "kelime" boşluk içeriyorsa ("C C +") parçalara ayırır; parçaların
/// yatay konumu karakter sırasına göre tahmin edilir.
Iterable<PdfWord> _split(String text, Rect bounds) sync* {
  if (text.trim().isEmpty) return;
  if (!text.contains(' ')) {
    yield PdfWord(text, bounds.left, bounds.top);
    return;
  }
  final perChar = text.isEmpty ? 0.0 : bounds.width / text.length;
  for (final m in RegExp(r'\S+').allMatches(text)) {
    yield PdfWord(m.group(0)!, bounds.left + perChar * m.start, bounds.top);
  }
}
