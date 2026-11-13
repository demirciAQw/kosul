import 'package:flutter_test/flutter_test.dart';

import '../tool/shortcut_patch.dart';

void main() {
  const m =
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <application android:label="kocum">\n'
      '        <activity\n            android:name=".MainActivity"\n            android:exported="true">\n'
      '            <intent-filter/>\n'
      '        </activity>\n'
      '    </application>\n</manifest>\n';

  test('kısayol ve derin bağlantı MainActivity içine bir kez eklenir', () {
    final out = patchShortcutManifest(m);
    expect(out, contains('android:resource="@xml/kocum_kisayollar"'));
    expect(out, contains('flutter_deeplinking_enabled'));
    expect(out.indexOf('android.app.shortcuts'), lessThan(out.indexOf('</activity>')));
    expect(out.indexOf('android.app.shortcuts'), greaterThan(out.indexOf('.MainActivity')));
    expect(patchShortcutManifest(out), out);
  });

  test('MainActivity yoksa dokunulmaz', () {
    const bos = '<manifest><application></application></manifest>';
    expect(patchShortcutManifest(bos), bos);
  });

  test('kısayol Anlık yazma adresini açar', () {
    final x = kisayolXml('com.kocum.kocum');
    expect(x, contains('android:targetClass="com.kocum.kocum.MainActivity"'));
    expect(x, contains('kocum://ac/anlik?yaz=1'));
    expect(kisayolMetinleri, contains('Anlık yaz'));
  });
}
