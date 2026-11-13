/// Bilgisayarla eşitleme (v8.5) için ağ ayarları:
///  - INTERNET: release APK'da varsayılan olarak yok; yerel ağ bağlantısı da bu izni ister.
///  - CHANGE_WIFI_MULTICAST_STATE: mDNS ile koçu bulmak için.
///  - usesCleartextTraffic: koç sunucusu yerel ağda düz HTTP konuşur (Android 9+ bunu
///    varsayılan olarak engeller). Uygulama internete hiç çıkmaz.
library;

const _izinler = ['android.permission.INTERNET', 'android.permission.CHANGE_WIFI_MULTICAST_STATE'];

String patchNetworkManifest(String manifest) {
  var s = manifest;
  for (final izin in _izinler) {
    if (s.contains('"$izin"')) continue;
    s = s.replaceFirst('<application', '<uses-permission android:name="$izin"/>\n    <application');
  }
  if (!s.contains('android:usesCleartextTraffic')) {
    s = s.replaceFirst(RegExp(r'<application(?=\s)'), '<application\n        android:usesCleartextTraffic="true"');
  }
  return s;
}
