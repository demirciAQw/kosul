import 'package:flutter_test/flutter_test.dart';

import '../tool/camera_patch.dart';

void main() {
  test('mikrofon izni manifestten çıkarılır; tools ad alanı eklenir; iki kez eklenmez', () {
    const m = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <application android:label="kocum">\n    </application>\n</manifest>\n';
    final out = removeAudioPermission(m);
    expect(out, contains('xmlns:tools="http://schemas.android.com/tools"'));
    expect(out, contains('android.permission.RECORD_AUDIO" tools:node="remove"'));
    expect(out.indexOf('RECORD_AUDIO'), lessThan(out.indexOf('<application')));
    expect(removeAudioPermission(out), out);
  });
}
