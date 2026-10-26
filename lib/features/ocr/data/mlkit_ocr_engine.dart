import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/ocr.dart';
import '../domain/question_text.dart';

/// ML Kit Latin metin tanıma (Türkçe harfler dahil); model uygulamaya gömülü,
/// internet gerekmez. Tanıyıcı bir kez açılır ve uygulama boyunca bellekte
/// durur: her fotoğrafta yeniden yüklenmez.
class MlKitOcrEngine implements OcrEngine {
  TextRecognizer? _recognizer;

  @override
  Future<List<OcrLine>> recognize(String absolutePath) async {
    final recognizer = _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final result = await recognizer.processImage(InputImage.fromFilePath(absolutePath));
    return [
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrLine(
            line.text,
            left: line.boundingBox.left,
            top: line.boundingBox.top,
            height: line.boundingBox.height,
            width: line.boundingBox.width,
            confidence: line.confidence ?? 1,
            angle: line.angle ?? 0,
            words: [
              for (final e in line.elements)
                OcrWord(
                  e.text,
                  left: e.boundingBox.left,
                  top: e.boundingBox.top,
                  width: e.boundingBox.width,
                  height: e.boundingBox.height,
                  confidence: e.confidence ?? 1,
                ),
            ],
          ),
    ];
  }
}
