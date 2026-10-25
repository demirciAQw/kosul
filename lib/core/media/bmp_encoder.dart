import 'dart:typed_data';

/// Ham RGBA pikselleri 24 bitlik BMP'ye çevirir (sıkıştırmasız).
///
/// PNG kodlaması büyük görüntülerde telefonda saniyeler sürebilir; BMP yalnızca
/// baytları yeniden dizmektir. Android'in görüntü çözücüsü BMP'yi doğrudan açar,
/// sıkıştırıcı da buradan WebP üretir. Satırlar aşağıdan yukarı, her satır
/// 4 baytın katına doldurulur.
Uint8List rgbaToBmp(Uint8List rgba, int width, int height) {
  final row = (width * 3 + 3) & ~3;
  final size = 54 + row * height;
  final out = Uint8List(size);
  final header = ByteData.sublistView(out, 0, 54)
    ..setUint8(0, 0x42) // 'B'
    ..setUint8(1, 0x4D) // 'M'
    ..setUint32(2, size, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little) // BITMAPINFOHEADER
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, height, Endian.little) // pozitif: aşağıdan yukarı
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(30, 0, Endian.little) // BI_RGB
    ..setUint32(34, row * height, Endian.little)
    ..setInt32(38, 2835, Endian.little)
    ..setInt32(42, 2835, Endian.little);
  assert(header.lengthInBytes == 54);
  for (var y = 0; y < height; y++) {
    var src = (height - 1 - y) * width * 4;
    var dst = 54 + y * row;
    for (var x = 0; x < width; x++) {
      out[dst] = rgba[src + 2]; // B
      out[dst + 1] = rgba[src + 1]; // G
      out[dst + 2] = rgba[src]; // R
      src += 4;
      dst += 3;
    }
  }
  return out;
}

/// [compute] ile arka planda çağrılabilen biçim.
Uint8List rgbaToBmpTask((Uint8List, int, int) job) => rgbaToBmp(job.$1, job.$2, job.$3);
