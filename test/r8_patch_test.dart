import 'package:flutter_test/flutter_test.dart';

import '../tool/r8_patch.dart';

void main() {
  test('proguard-rules.pro: dört dil okuyucusu için uyarı kapatılır; iki kez eklenmez', () {
    final fresh = patchProguardRules(null);
    for (final lang in ['chinese', 'devanagari', 'japanese', 'korean']) {
      expect(fresh, contains('-dontwarn com.google.mlkit.vision.text.$lang.**'));
    }
    expect(patchProguardRules(fresh), fresh);
    final kept = patchProguardRules('-keep class foo.Bar');
    expect(kept, startsWith('-keep class foo.Bar'));
    expect(kept, contains(r8Marker));
  });

  test('Gradle: sürüm derlemesi kuralları kullanır; iki kez eklenmez', () {
    final kts = patchR8Kts('android {}\n');
    expect(kts, contains('getByName("release")'));
    expect(kts, contains('proguardFiles("proguard-rules.pro")'));
    expect(patchR8Kts(kts), kts);
    final groovy = patchR8Groovy('android {}\n');
    expect(groovy, contains("proguardFiles 'proguard-rules.pro'"));
    expect(patchR8Groovy(groovy), groovy);
  });
}
