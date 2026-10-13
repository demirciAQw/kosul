// Android ayarlarını yapar. Tekrar çalıştırmak güvenlidir (idempotent).
//   dart tool/patch_android.dart
//
//  - Bildirim izni (oturum kronometresi için)
//  - Uygulama adı: Koçum
//  - flutter_local_notifications için core library desugaring
//  - Sabit imza: android/key.properties varsa release APK onunla imzalanır
//    (yoksa eskisi gibi hata ayıklama anahtarı kullanılır)
//  - Eski eklentileri yeni Android SDK ile derleme
//
// v0.2: harici kırpıcı (uCrop / image_cropper) kaldırıldı; kırpma uygulama içinde.
import 'dart:io';

const _desugarVersion = '2.1.4';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('android/ klasörü bulunamadı. Önce tool/setup.sh (ya da setup.bat) çalıştır.');
    exit(1);
  }
  _patchManifest(manifest);

  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  if (kts.existsSync()) {
    _patchKts(kts);
    _patchSigningKts(kts);
  } else if (groovy.existsSync()) {
    _patchGroovy(groovy);
    _patchSigningGroovy(groovy);
  } else {
    stderr.writeln('android/app/build.gradle(.kts) bulunamadı.');
    exit(1);
  }
  _patchRootGradle();
  _copyLauncherIcons();
  stdout.writeln('Android ayarları tamam.');
}

/// Koçum simgesi: tool/android_icon/res altındakiler (tool/make_icon.py ile
/// üretilir) Flutter'ın varsayılan simgelerinin üzerine kopyalanır.
void _copyLauncherIcons() {
  final src = Directory('tool/android_icon/res');
  final dst = Directory('android/app/src/main/res');
  if (!src.existsSync() || !dst.existsSync()) {
    stderr.writeln('Uyarı: uygulama simgesi kopyalanamadı (klasör yok).');
    return;
  }
  var count = 0;
  for (final entity in src.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(src.path.length + 1);
    final target = File('${dst.path}/$relative');
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
    count++;
  }
  stdout.writeln('Uygulama simgesi: $count dosya kopyalandı.');
}

void _patchManifest(File file) {
  var s = file.readAsStringSync();

  if (!s.contains('POST_NOTIFICATIONS')) {
    s = s.replaceFirst(
      '<application',
      '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application',
    );
  }
  // Eski sürümün eklediği uCrop etkinliği: kütüphane artık yok, kaynağı da yok.
  s = s.replaceAll(
    RegExp(r'\s*<activity\s+android:name="com\.yalantis\.ucrop\.UCropActivity"[^>]*/>'),
    '',
  );
  s = s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Koçum"');
  file.writeAsStringSync(s);
}

void _patchKts(File file) {
  var s = file.readAsStringSync();
  if (s.contains('isCoreLibraryDesugaringEnabled')) return;

  if (s.contains('compileOptions {')) {
    s = s.replaceFirst('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true');
  } else {
    s = s.replaceFirst(
      'android {',
      'android {\n    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n    }',
    );
  }
  s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:$_desugarVersion")\n}\n';
  file.writeAsStringSync(s);
}

void _patchGroovy(File file) {
  var s = file.readAsStringSync();
  if (s.contains('coreLibraryDesugaringEnabled')) return;

  if (s.contains('compileOptions {')) {
    s = s.replaceFirst('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true');
  } else {
    s = s.replaceFirst(
      'android {',
      'android {\n    compileOptions {\n        coreLibraryDesugaringEnabled true\n    }',
    );
  }
  s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:$_desugarVersion'\n}\n";
  file.writeAsStringSync(s);
}

// ───────────────────────── Sabit imza ─────────────────────────
//
// Her derleme farklı bir hata ayıklama anahtarıyla imzalanırsa Android yeni
// sürümü eskisinin üstüne kurmaz; kaldır-yükle gerekir ve veriler silinir.
// key.properties (CI'da GitHub Secrets'tan üretilir) varsa release APK hep
// aynı anahtarla imzalanır ve güncellemeler üstüne kurulur.

const _signingMarker = 'kocum-release-signing';

   void _patchSigningKts(File file) {
     var s = file.readAsStringSync();
     if (s.contains(_signingMarker)) return;
     // Kotlin DSL'de import dosyanın en başında olmalı.
     s = 'import java.util.Properties\n\n$s';

  const header = '''
// $_signingMarker: android/key.properties varsa sabit anahtarla imzala.
val kocumKeystoreProperties = Properties()
val kocumKeystoreFile = rootProject.file("key.properties")
if (kocumKeystoreFile.exists()) {
    kocumKeystoreFile.inputStream().use { kocumKeystoreProperties.load(it) }
}

''';
  const configs = '''
    signingConfigs {
        create("release") {
            if (kocumKeystoreFile.exists()) {
                keyAlias = kocumKeystoreProperties.getProperty("keyAlias")
                keyPassword = kocumKeystoreProperties.getProperty("keyPassword")
                storeFile = kocumKeystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = kocumKeystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {''';
  const pick =
      'signingConfig = if (kocumKeystoreFile.exists()) signingConfigs.getByName("release") '
      'else signingConfigs.getByName("debug")';

  final androidBlock = RegExp(r'^android \{', multiLine: true);
  if (!androidBlock.hasMatch(s) || !s.contains('    buildTypes {')) {
    stderr.writeln('Uyarı: build.gradle.kts beklenen biçimde değil; sabit imza eklenemedi.');
    return;
  }
  s = s.replaceFirst(androidBlock, '${header}android {');
  s = s.replaceFirst('    buildTypes {', configs);
  if (s.contains('signingConfig = signingConfigs.getByName("debug")')) {
    s = s.replaceFirst('signingConfig = signingConfigs.getByName("debug")', pick);
  } else {
    s = s.replaceFirst(RegExp(r'release \{'), 'release {\n            $pick');
  }
  file.writeAsStringSync(s);
}

void _patchSigningGroovy(File file) {
  var s = file.readAsStringSync();
  if (s.contains(_signingMarker)) return;

  const header = '''
// $_signingMarker: android/key.properties varsa sabit anahtarla imzala.
def kocumKeystoreProperties = new Properties()
def kocumKeystoreFile = rootProject.file('key.properties')
if (kocumKeystoreFile.exists()) {
    kocumKeystoreFile.withReader('UTF-8') { kocumKeystoreProperties.load(it) }
}

''';
  const configs = '''
    signingConfigs {
        release {
            if (kocumKeystoreFile.exists()) {
                keyAlias kocumKeystoreProperties['keyAlias']
                keyPassword kocumKeystoreProperties['keyPassword']
                storeFile file(kocumKeystoreProperties['storeFile'])
                storePassword kocumKeystoreProperties['storePassword']
            }
        }
    }

    buildTypes {''';
  const pick = 'signingConfig kocumKeystoreFile.exists() ? signingConfigs.release : signingConfigs.debug';

  final androidBlock = RegExp(r'^android \{', multiLine: true);
  if (!androidBlock.hasMatch(s) || !s.contains('    buildTypes {')) {
    stderr.writeln('Uyarı: build.gradle beklenen biçimde değil; sabit imza eklenemedi.');
    return;
  }
  s = s.replaceFirst(androidBlock, '${header}android {');
  s = s.replaceFirst('    buildTypes {', configs);
  s = s.replaceFirst(RegExp(r'signingConfig\s*=?\s*signingConfigs\.debug'), pick);
  file.writeAsStringSync(s);
}

const _marker = 'kocum-force-compile-sdk';

/// Bazı eklentiler eski bir compileSdk ile yayınlanmış
/// ama bağımlılıkları 34 ve üstünü istiyor; derleme "checkReleaseAarMetadata"
/// adımında düşüyor. Tüm kütüphane modüllerini yeni SDK ile derleriz.
void _patchRootGradle() {
  final kts = File('android/build.gradle.kts');
  final groovy = File('android/build.gradle');

  if (kts.existsSync()) {
    final s = kts.readAsStringSync();
    if (s.contains(_marker)) return;
    kts.writeAsStringSync(s + _rootKts);
  } else if (groovy.existsSync()) {
    final s = groovy.readAsStringSync();
    if (s.contains(_marker)) return;
    groovy.writeAsStringSync(s + _rootGroovy);
  } else {
    stderr.writeln('android/build.gradle(.kts) bulunamadı.');
    exit(1);
  }
}

// Eklenti sınıflarına bağlı olmamak için yansıma (reflection) kullanılır;
// kök betiğin sınıf yolunda Android eklentisi olmayabilir.
const _rootKts = r'''

// kocum-force-compile-sdk: eski eklentileri yeni Android SDK ile derle.
subprojects {
    val forceCompileSdk: Project.() -> Unit = {
        if (plugins.hasPlugin("com.android.library")) {
            val androidExt = extensions.findByName("android")
            val setter = androidExt?.javaClass?.methods?.firstOrNull {
                (it.name == "compileSdkVersion" || it.name == "setCompileSdkVersion") &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }
            setter?.invoke(androidExt, 36)
        }
    }
    if (state.executed) forceCompileSdk() else afterEvaluate { forceCompileSdk() }
}
''';

const _rootGroovy = r'''

// kocum-force-compile-sdk: eski eklentileri yeni Android SDK ile derle.
subprojects {
    def forceSdk = { p ->
        if (p.plugins.hasPlugin('com.android.library')) {
            p.android.compileSdkVersion 36
        }
    }
    if (project.state.executed) {
        forceSdk(project)
    } else {
        project.afterEvaluate { forceSdk(project) }
    }
}
''';
