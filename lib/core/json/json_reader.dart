/// JSON'dan tip güvenli ve yol (path) bilgili okuma.
///
/// Topluluk şablonları elle düzenlenebildiği için her hata, sorunun tam
/// yerini söyler: `$.units[2].children[0].pageEnd`.
library;

class JsonFormatException implements Exception {
  const JsonFormatException(this.path, this.message);
  final String path;
  final String message;

  @override
  String toString() => '$message ($path)';
}

class JsonReader {
  JsonReader(this.raw, [this.path = r'$']);

  factory JsonReader.root(Object? decoded) {
    if (decoded is Map<String, dynamic>) return JsonReader(decoded);
    throw const JsonFormatException(r'$', 'Kök öğe bir JSON nesnesi olmalı');
  }

  final Map<String, dynamic> raw;
  final String path;

  String at(String key) => '$path.$key';

  String requireString(String key, {int maxLength = 500}) =>
      optString(key, maxLength: maxLength) ??
      (throw JsonFormatException(at(key), 'Zorunlu metin alanı eksik'));

  String? optString(String key, {int maxLength = 500}) {
    final value = raw[key];
    if (value == null) return null;
    if (value is! String) throw JsonFormatException(at(key), 'Metin bekleniyordu');
    final trimmed = value.trim();
    if (trimmed.length > maxLength) {
      throw JsonFormatException(at(key), 'En fazla $maxLength karakter olabilir');
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  int requireInt(String key, {int? min, int? max}) =>
      optInt(key, min: min, max: max) ??
      (throw JsonFormatException(at(key), 'Zorunlu tam sayı alanı eksik'));

  int? optInt(String key, {int? min, int? max}) {
    final value = raw[key];
    if (value == null) return null;
    final int parsed;
    if (value is int) {
      parsed = value;
    } else if (value is double && value == value.truncateToDouble()) {
      parsed = value.toInt(); // 12.0 gibi yazılmış tam sayıları kabul et
    } else {
      throw JsonFormatException(at(key), 'Tam sayı bekleniyordu');
    }
    _checkRange(key, parsed, min, max);
    return parsed;
  }

  double requireDouble(String key, {double? min, double? max}) {
    final value = raw[key];
    if (value is! num || value.isNaN || value.isInfinite) {
      throw JsonFormatException(at(key), 'Sayı bekleniyordu');
    }
    _checkRange(key, value, min, max);
    return value.toDouble();
  }

  JsonReader requireObject(String key) {
    final value = raw[key];
    if (value is Map<String, dynamic>) return JsonReader(value, at(key));
    throw JsonFormatException(at(key), 'Nesne bekleniyordu');
  }

  List<JsonReader> objectList(String key, {bool required = false}) {
    final value = raw[key];
    if (value == null) {
      if (required) throw JsonFormatException(at(key), 'Zorunlu liste eksik');
      return const [];
    }
    if (value is! List) throw JsonFormatException(at(key), 'Liste bekleniyordu');
    final readers = <JsonReader>[];
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      final itemPath = '${at(key)}[$i]';
      if (item is! Map<String, dynamic>) throw JsonFormatException(itemPath, 'Nesne bekleniyordu');
      readers.add(JsonReader(item, itemPath));
    }
    return readers;
  }

  List<String> stringList(String key) {
    final value = raw[key];
    if (value == null) return const [];
    if (value is! List) throw JsonFormatException(at(key), 'Liste bekleniyordu');
    final out = <String>[];
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is! String || item.trim().isEmpty) {
        throw JsonFormatException('${at(key)}[$i]', 'Boş olmayan metin bekleniyordu');
      }
      out.add(item.trim());
    }
    return out;
  }

  void _checkRange(String key, num value, num? min, num? max) {
    if ((min != null && value < min) || (max != null && value > max)) {
      throw JsonFormatException(at(key), '${min ?? '-∞'} ile ${max ?? '∞'} arasında olmalı');
    }
  }
}
