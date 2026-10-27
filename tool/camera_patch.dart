/// Kamera eklentisi uygulamaya mikrofon izni de ekler (video için); Koçum ses
/// kaydetmez. İzin birleştirilmiş manifestten çıkarılır.
library;

const _remove = '<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove"/>';

String removeAudioPermission(String manifest) {
  if (manifest.contains(_remove)) return manifest;
  var s = manifest;
  if (!s.contains('xmlns:tools=')) {
    s = s.replaceFirst('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ');
  }
  return s.replaceFirst('<application', '$_remove\n    <application');
}
