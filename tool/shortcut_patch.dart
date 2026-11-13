/// Android uygulama kısayolu "Anlık yaz" (v8.6): simgeye uzun basınca çıkar,
/// doğrudan Anlık yazma alanını açar (kocum://ac/anlik?yaz=1 → /anlik?yaz=1).
///  - res/xml/kocum_kisayollar.xml: kısayol tanımı
///  - res/values/kocum_kisayol_metinleri.xml: kısayolun adı (kaynak olmak zorunda)
///  - Manifest: MainActivity'ye kısayol bilgisi ve Flutter derin bağlantısı
library;

const kisayolMetinleri = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="kocum_anlik_yaz">Anlık yaz</string>
</resources>
''';

String kisayolXml(String paket) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
    <shortcut
        android:shortcutId="anlik_yaz"
        android:enabled="true"
        android:icon="@mipmap/ic_launcher"
        android:shortcutShortLabel="@string/kocum_anlik_yaz"
        android:shortcutLongLabel="@string/kocum_anlik_yaz">
        <intent
            android:action="android.intent.action.VIEW"
            android:targetPackage="$paket"
            android:targetClass="$paket.MainActivity"
            android:data="kocum://ac/anlik?yaz=1" />
    </shortcut>
</shortcuts>
''';

/// MainActivity'nin `<activity>` bloğuna kısayol ve derin bağlantı bilgisi eklenir.
String patchShortcutManifest(String manifest) {
  if (manifest.contains('android.app.shortcuts')) return manifest;
  final bas = RegExp(r'<activity[^>]*android:name="\.MainActivity"').firstMatch(manifest);
  if (bas == null) return manifest;
  final son = manifest.indexOf('</activity>', bas.end);
  if (son < 0) return manifest;
  const ek =
      '    <meta-data android:name="android.app.shortcuts" android:resource="@xml/kocum_kisayollar" />\n'
      '            <meta-data android:name="flutter_deeplinking_enabled" android:value="true" />\n'
      '        ';
  return manifest.substring(0, son) + ek + manifest.substring(son);
}
