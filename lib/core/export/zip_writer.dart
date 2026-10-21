import 'dart:convert';
import 'dart:typed_data';

/// Bağımlılıksız, sıkıştırmasız ("stored") ZIP yazıcı. Fotoğraflar zaten
/// sıkıştırılmış olduğundan sıkıştırma kazandırmaz. Dosya adları UTF-8
/// (Türkçe karakterler korunur); klasörler adın içinde "/" ile verilir.
class ZipWriter {
  ZipWriter({DateTime? time}) : _time = time ?? DateTime.now();

  final DateTime _time;
  final _local = BytesBuilder(copy: false);
  final _central = BytesBuilder(copy: false);
  var _count = 0;
  final _names = <String>{};

  int get length => _count;

  /// Aynı ad ikinci kez gelirse "ad (2).uzantı" yapılır.
  String add(String name, List<int> data) {
    final unique = _unique(name);
    final nameBytes = utf8.encode(unique);
    final crc = crc32(data);
    final offset = _local.length;
    final t = _dosTime(_time), d = _dosDate(_time);

    final lh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little) // sürüm
      ..setUint16(6, 0x0800, Endian.little) // UTF-8 ad
      ..setUint16(8, 0, Endian.little) // stored
      ..setUint16(10, t, Endian.little)
      ..setUint16(12, d, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    _local
      ..add(lh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);

    final ch = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, t, Endian.little)
      ..setUint16(14, d, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint16(30, 0, Endian.little)
      ..setUint16(32, 0, Endian.little)
      ..setUint16(34, 0, Endian.little)
      ..setUint16(36, 0, Endian.little)
      ..setUint32(38, 0, Endian.little)
      ..setUint32(42, offset, Endian.little);
    _central
      ..add(ch.buffer.asUint8List())
      ..add(nameBytes);
    _count++;
    return unique;
  }

  void addText(String name, String text, {bool bom = false}) =>
      add(name, [if (bom) ...const [0xEF, 0xBB, 0xBF], ...utf8.encode(text)]);

  Uint8List finish() {
    final centralBytes = _central.toBytes();
    final offset = _local.length;
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, _count, Endian.little)
      ..setUint16(10, _count, Endian.little)
      ..setUint32(12, centralBytes.length, Endian.little)
      ..setUint32(16, offset, Endian.little)
      ..setUint16(20, 0, Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(_local.toBytes())
      ..add(centralBytes)
      ..add(end.buffer.asUint8List());
    return out.toBytes();
  }

  String _unique(String name) {
    if (_names.add(name)) return name;
    final dot = name.lastIndexOf('.');
    final slash = name.lastIndexOf('/');
    final hasExt = dot > slash + 1;
    final base = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';
    for (var i = 2;; i++) {
      final candidate = '$base ($i)$ext';
      if (_names.add(candidate)) return candidate;
    }
  }

  static int _dosTime(DateTime t) => (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
  static int _dosDate(DateTime t) => ((t.year - 1980).clamp(0, 127) << 9) | (t.month << 5) | t.day;
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// CRC-32 (ZIP/PNG ile aynı). "123456789" → 0xCBF43926.
int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Dosya adında sorun çıkaran karakterleri temizler; Türkçe harfler kalır.
String safeFileName(String s, {int maxLength = 80}) {
  var t = s
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(' ', '_');
  if (t.length > maxLength) t = t.substring(0, maxLength);
  return t.isEmpty ? 'adsiz' : t;
}
