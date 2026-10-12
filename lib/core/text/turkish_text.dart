/// Türkçe'ye duyarlı metin normalizasyonu ve bulanık benzerlik ölçümü.
/// Kitap konu adlarını MEB ağacıyla eşleştirmek ve aramada kullanılır.
library;

const _fold = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u'};
final _nonAlnum = RegExp(r'[^a-z0-9]+');

/// "YAŞ PROBLEMLERİ" → "yas problemleri", "Kâr-Zarar" → "kar zarar"
///
/// Dart'ın `toLowerCase()`'i yerel ayardan bağımsızdır: 'İ' → 'i̇' (noktalı
/// birleşik karakter) üretir. Bu yüzden 'İ' ve 'I' önce elle çevrilir.
String normalizeTr(String input) {
  final lowered = input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  final buffer = StringBuffer();
  for (final ch in lowered.split('')) {
    buffer.write(_fold[ch] ?? ch);
  }
  return buffer.toString().replaceAll(_nonAlnum, ' ').trim();
}

/// Karakter ikilileri; Türkçe'nin ek yapısına ("problemi" / "problemleri")
/// kelime bazlı karşılaştırmadan çok daha toleranslıdır.
Set<String> bigramsOf(String normalized) {
  final s = ' $normalized ';
  return {for (var i = 0; i < s.length - 1; i++) s.substring(i, i + 2)};
}

/// Sørensen–Dice katsayısı: 0 (hiç benzemez) … 1 (aynı).
double diceCoefficient(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final (small, large) = a.length <= b.length ? (a, b) : (b, a);
  final common = small.where(large.contains).length;
  return 2 * common / (a.length + b.length);
}

/// Türkçe küçük harf: "İşlem hatası" → "işlem hatası" (noktasız/noktalı i doğru).
String lowerTr(String input) => input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
