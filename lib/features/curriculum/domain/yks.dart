import 'curriculum.dart';

/// YKS oturumlarındaki dersler ve soru sayıları (ÖSYM yapısı).
///
/// Ders anahtarı her yerde aynıdır: [subjectKey] → "TYT Matematik".
/// Kartlar, oturumlar ve denemeler bu anahtarla birleşir.
class ExamSubject {
  const ExamSubject(this.examType, this.name, this.questions, {this.group});

  final String examType; // TYT | AYT | YDT
  final String name; // "Matematik"
  final int questions;

  /// Aynı testte birlikte sorulan dersler: "Sosyal Bilimler", "Fen Bilimleri".
  final String? group;

  String get key => subjectKey(examType, name);
}

abstract final class Yks {
  static const tyt = <ExamSubject>[
    ExamSubject('TYT', 'Türkçe', 40),
    ExamSubject('TYT', 'Tarih', 5, group: 'Sosyal Bilimler'),
    ExamSubject('TYT', 'Coğrafya', 5, group: 'Sosyal Bilimler'),
    ExamSubject('TYT', 'Felsefe', 5, group: 'Sosyal Bilimler'),
    ExamSubject('TYT', 'Din Kültürü', 5, group: 'Sosyal Bilimler'),
    ExamSubject('TYT', 'Matematik', 40),
    ExamSubject('TYT', 'Fizik', 7, group: 'Fen Bilimleri'),
    ExamSubject('TYT', 'Kimya', 7, group: 'Fen Bilimleri'),
    ExamSubject('TYT', 'Biyoloji', 6, group: 'Fen Bilimleri'),
  ];

  static const ayt = <ExamSubject>[
    ExamSubject('AYT', 'Matematik', 40),
    ExamSubject('AYT', 'Fizik', 14, group: 'Fen Bilimleri'),
    ExamSubject('AYT', 'Kimya', 13, group: 'Fen Bilimleri'),
    ExamSubject('AYT', 'Biyoloji', 13, group: 'Fen Bilimleri'),
    ExamSubject('AYT', 'Edebiyat', 24, group: 'Edebiyat-Sosyal Bilimler 1'),
    ExamSubject('AYT', 'Tarih-1', 10, group: 'Edebiyat-Sosyal Bilimler 1'),
    ExamSubject('AYT', 'Coğrafya-1', 6, group: 'Edebiyat-Sosyal Bilimler 1'),
    ExamSubject('AYT', 'Tarih-2', 11, group: 'Sosyal Bilimler 2'),
    ExamSubject('AYT', 'Coğrafya-2', 11, group: 'Sosyal Bilimler 2'),
    ExamSubject('AYT', 'Felsefe Grubu', 12, group: 'Sosyal Bilimler 2'),
    ExamSubject('AYT', 'Din Kültürü', 6, group: 'Sosyal Bilimler 2'),
  ];

  static const ydt = <ExamSubject>[
    ExamSubject('YDT', 'Yabancı Dil', 80),
  ];

  static const all = <ExamSubject>[...tyt, ...ayt, ...ydt];

  /// AYT puan türlerine göre girilen dersler (deneme formunu hazırlamak için).
  static const aytFields = <String, List<String>>{
    'Sayısal': ['Matematik', 'Fizik', 'Kimya', 'Biyoloji'],
    'Eşit Ağırlık': ['Matematik', 'Edebiyat', 'Tarih-1', 'Coğrafya-1'],
    'Sözel': ['Edebiyat', 'Tarih-1', 'Coğrafya-1', 'Tarih-2', 'Coğrafya-2', 'Felsefe Grubu', 'Din Kültürü'],
    'Tümü': [
      'Matematik',
      'Fizik',
      'Kimya',
      'Biyoloji',
      'Edebiyat',
      'Tarih-1',
      'Coğrafya-1',
      'Tarih-2',
      'Coğrafya-2',
      'Felsefe Grubu',
      'Din Kültürü',
    ],
  };

  static ExamSubject? byKey(String key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }

  static List<ExamSubject> ofExam(String examType) =>
      [for (final s in all) if (s.examType == examType) s];
}

/// "TYT Matematik" → "Matematik"
String subjectName(String key) {
  final space = key.indexOf(' ');
  return space < 0 ? key : key.substring(space + 1);
}

/// Seçim menüleri için tüm ders anahtarları: YKS dersleri + müfredat + kitaplar.
/// YKS sırası korunur, fazladan gelenler (ör. "TYT Geometri") sona eklenir.
List<String> allSubjectKeys({Iterable<String> extra = const []}) {
  final keys = <String>[for (final s in Yks.all) s.key];
  final known = keys.toSet();
  final more = {for (final e in extra) if (!known.contains(e)) e}.toList()..sort();
  return [...keys, ...more];
}
