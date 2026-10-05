import 'package:uuid/uuid.dart';

/// Saat kaynağı; testlerde sabit zaman enjekte edebilmek için.
typedef Clock = DateTime Function();

abstract interface class IdGenerator {
  String next();
}

/// UUID v7 zamana göre sıralıdır: SQLite B-tree indekslerinde v4'e göre
/// çok daha az sayfa bölünmesi yaratır (on binlerce kayıtta fark eder).
class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();
  static final _uuid = Uuid();

  @override
  String next() => _uuid.v7();
}
