import 'package:flutter_test/flutter_test.dart';

import '../tool/network_patch.dart';

void main() {
  const m =
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <application\n        android:label="kocum">\n    </application>\n</manifest>\n';

  test('internet ve mDNS izni, düz HTTP izni eklenir; iki kez eklenmez', () {
    final out = patchNetworkManifest(m);
    expect(out, contains('<uses-permission android:name="android.permission.INTERNET"/>'));
    expect(out, contains('android.permission.CHANGE_WIFI_MULTICAST_STATE'));
    expect(out, contains('android:usesCleartextTraffic="true"'));
    expect(out.indexOf('INTERNET'), lessThan(out.indexOf('<application')));
    expect(RegExp('<application').allMatches(out).length, 1);
    expect(patchNetworkManifest(out), out);
  });

  test('izin zaten varsa tekrar yazılmaz', () {
    final once = m.replaceFirst(
      '<application',
      '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
    );
    final out = patchNetworkManifest(once);
    expect(RegExp('permission.INTERNET').allMatches(out).length, 1);
  });
}
