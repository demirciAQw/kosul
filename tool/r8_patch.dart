/// R8 (küçültme) kuralları. ML Kit metin okuma eklentisi kodunda Çince,
/// Devanagari, Japonca ve Korece okuyuculara da atıf yapar; uygulama yalnızca
/// Latin modelini içerdiği için bu sınıflar yoktur ve R8 "eksik sınıf" diye
/// durur. Bilerek yoklar: uyarı kapatılır (boyut artmaz).
///
/// Ayrıca ML Kit iç bileşenlerini adla (yansıma ile) bulur; R8 bunları silip
/// yeniden adlandırınca sürüm derlemesinde okuma "null" hatasıyla düşer. ML Kit
/// ve eklenti sınıfları korunur; uygulamanın geri kalanı küçültülmeye devam eder.
library;

const r8Marker = '# kocum-r8';

const r8Rules = '''
$r8Marker
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
# ML Kit bileşenleri yansıma ile bulunur: R8 silmesin, yeniden adlandırmasın.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
''';

/// proguard-rules.pro: kurallar eklenir (varsa korunur, iki kez eklenmez).
String patchProguardRules(String? existing) {
  final s = existing ?? '';
  if (s.contains(r8Marker)) return s;
  return s.isEmpty ? r8Rules : '${s.trimRight()}\n\n$r8Rules';
}

/// build.gradle.kts: sürüm derlemesi kuralları açıkça kullanır.
String patchR8Kts(String s) {
  if (s.contains('// kocum-r8')) return s;
  return '$s\n// kocum-r8\nandroid {\n    buildTypes {\n        getByName("release") {\n'
      '            proguardFiles("proguard-rules.pro")\n        }\n    }\n}\n';
}

/// build.gradle (Groovy).
String patchR8Groovy(String s) {
  if (s.contains('// kocum-r8')) return s;
  return "$s\n// kocum-r8\nandroid {\n    buildTypes {\n        release {\n"
      "            proguardFiles 'proguard-rules.pro'\n        }\n    }\n}\n";
}
