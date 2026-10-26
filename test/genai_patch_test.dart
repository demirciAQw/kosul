import 'package:flutter_test/flutter_test.dart';

import '../tool/genai_patch.dart';

void main() {
  const kts = '''
android {
    defaultConfig {
        applicationId = "com.kocum.kocum"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
    }
}
''';

  test('build.gradle.kts: minSdk 31 ve bağımlılık; ikinci kez değişmez', () {
    final once = patchGenAiKts(kts);
    expect(once, contains('minSdk = 31'));
    expect(once, isNot(contains('flutter.minSdkVersion')));
    expect(once, contains('implementation("$genAiDependency")'));
    expect(once, contains('targetSdk = flutter.targetSdkVersion')); // dokunulmaz
    expect(patchGenAiKts(once), once);
  });

  test('build.gradle (Groovy)', () {
    final out = patchGenAiGroovy('android {\n    defaultConfig {\n        minSdkVersion flutter.minSdkVersion\n    }\n}\n');
    expect(out, contains('minSdkVersion 31'));
    expect(out, contains("implementation '$genAiDependency'"));
    expect(patchGenAiGroovy(out), out);
  });

  test('MainActivity: paket korunur, kanal adı doğru, Kotlin şablonu güvenli', () {
    expect(packageOf('package com.kocum.kocum\n\nimport io.flutter.embedding.android.FlutterActivity\n'),
        'com.kocum.kocum');
    final kt = genAiMainActivity('com.kocum.kocum');
    expect(kt, startsWith('package com.kocum.kocum')); // Dart ilk boş satırı atar
    expect(kt, contains('"kocum/genai"'));
    expect(kt, isNot(contains(r'$'))); // Kotlin dizge şablonu yok
    expect('{'.allMatches(kt).length, '}'.allMatches(kt).length);
    expect('('.allMatches(kt).length, ')'.allMatches(kt).length);
  });
}
