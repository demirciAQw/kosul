// Android ayarlarını yapar. Tekrar çalıştırmak güvenlidir (idempotent).
//   dart tool/patch_android.dart
//
//  - Bildirim izni (oturum kronometresi için)
//  - Fotoğraf kırpma ekranı (uCrop)
//  - Uygulama adı: Koçum
//  - flutter_local_notifications için core library desugaring
//  - Eski eklentileri (ör. image_cropper, compileSdk 33) yeni Android SDK ile derleme
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
  } else if (groovy.existsSync()) {
    _patchGroovy(groovy);
  } else {
    stderr.writeln('android/app/build.gradle(.kts) bulunamadı.');
    exit(1);
  }
  _patchRootGradle();
  stdout.writeln('Android ayarları tamam.');
}

void _patchManifest(File file) {
  var s = file.readAsStringSync();

  if (!s.contains('POST_NOTIFICATIONS')) {
    s = s.replaceFirst(
      '<application',
      '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application',
    );
  }
  if (!s.contains('UCropActivity')) {
    s = s.replaceFirst(
      '</application>',
      '    <activity\n'
          '            android:name="com.yalantis.ucrop.UCropActivity"\n'
          '            android:screenOrientation="portrait"\n'
          '            android:theme="@style/Theme.AppCompat.Light.NoActionBar"/>\n'
          '    </application>',
    );
  }
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

const _marker = 'kocum-force-compile-sdk';

/// Bazı eklentiler eski bir compileSdk ile yayınlanmış (ör. image_cropper: 33)
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
