import 'package:flutter/material.dart';

/// Koçum'un renk paleti: Google'ın dört ana rengi, iki ton halinde.
///
/// Renk teorisi notları:
/// - Ana renk mavi (#1A73E8): odak ve güven; uzun ders oturumlarında gözü
///   yormayan, en nötr "etkin" renk. Düğmeler, seçim, ilerleme halkaları.
/// - Yeşil, kırmızı ve sarı yalnızca anlam taşır: doğru, yanlış, boş. Süs
///   olarak kullanılmaz; böylece bir bakışta "iyi / kötü / eksik" okunur.
/// - Zemin saf beyaz değil, çok açık gri (#F8F9FA) ile beyaz kartlar: kontrast
///   yumuşak, metin (#202124) yine de WCAG AA'nın üstünde.
/// - Koyu temada doygun renkler göz kamaştırmasın diye pastel tonlar (Google
///   koyu tema tonları) kullanılır.
abstract final class KocumColors {
  // Açık tema
  static const blue = Color(0xFF1A73E8);
  static const red = Color(0xFFD93025);
  static const yellow = Color(0xFFF9AB00);
  static const green = Color(0xFF1E8E3E);

  /// Sarı zeminde beyaz yazı okunmaz; "boş" balonları için koyu sarı.
  static const amber = Color(0xFFE37400);

  // Koyu tema
  static const blueDark = Color(0xFF8AB4F8);
  static const redDark = Color(0xFFF28B82);
  static const yellowDark = Color(0xFFFDD663);
  static const greenDark = Color(0xFF81C995);

  // Nötrler (Google gri skalası)
  static const grey900 = Color(0xFF202124);
  static const grey800 = Color(0xFF3C4043);
  static const grey700 = Color(0xFF5F6368);
  static const grey500 = Color(0xFF9AA0A6);
  static const grey300 = Color(0xFFDADCE0);
  static const grey200 = Color(0xFFE8EAED);
  static const grey100 = Color(0xFFF1F3F4);
  static const grey50 = Color(0xFFF8F9FA);

  // Anlam renkleri: her iki temada da beyaz yazıyla okunur orta tonlar.
  static const correct = green;
  static const wrong = red;
  static const blank = amber;

  /// İlerleme kademeleri (kitap haritası, net değişimi).
  static const good = green;
  static const fair = amber;
  static const weak = red;

  /// Yıldız (Güzel Sorular).
  static const star = yellow;

  /// Ana ekran kısayollarının renkleri: sırayla dönen dört Google rengi.
  static const accents = [blue, green, amber, red];

  /// Koyu temada doygun renkler göz kamaştırır ve koyu zeminde zor okunur;
  /// her ana rengin pastel karşılığı kullanılır. Bilinmeyen renk aynen döner.
  static Color adaptive(Color c, Brightness b) {
    if (b == Brightness.light) return c;
    if (c == blue) return blueDark;
    if (c == red) return redDark;
    if (c == green) return greenDark;
    if (c == yellow || c == amber) return yellowDark;
    if (c == grey700 || c == grey800 || c == grey900) return grey500;
    return c;
  }
}
