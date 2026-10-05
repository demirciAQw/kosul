// Android ayarlarını yapar. Tekrar çalıştırmak güvenlidir (idempotent).
//   dart tool/patch_android.dart
//
//  - Bildirim izni (oturum kronometresi için)
//  - Fotoğraf kırpma ekranı (uCrop)
//  - Uygulama adı: Koçum
//  - flutter_local_notifications için core library desugaring
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
