import 'package:flutter/services.dart';

/// ML Kit GenAI resim açıklaması (Gemini Nano, telefonda). Yalnızca destekleyen
/// cihazlarda çalışır; açıklamalar İngilizcedir. Köprü Android tarafında
/// (tool/genai_patch.dart ile üretilen MainActivity).
class GenAiDescriber {
  static const _channel = MethodChannel('kocum/genai');

  /// available | downloadable | downloading | unavailable | unknown | error: …
  Future<String> status() async {
    try {
      return await _channel.invokeMethod<String>('status') ?? 'unknown';
    } on MissingPluginException {
      return 'unavailable';
    } on PlatformException catch (e) {
      return 'error: ${e.message}';
    }
  }

  /// Modeli indirir (cihaz destekliyorsa); bitince durum döner.
  Future<String> download() async {
    try {
      return await _channel.invokeMethod<String>('download') ?? 'unknown';
    } on MissingPluginException {
      return 'unavailable';
    } on PlatformException catch (e) {
      return 'error: ${e.message}';
    }
  }

  /// [path] görüntüsünün kısa açıklaması; olmazsa null.
  Future<String?> describe(String path) async {
    try {
      final text = await _channel.invokeMethod<String>('describe', {'path': path});
      return (text == null || text.trim().isEmpty) ? null : text.trim();
    } catch (_) {
      return null;
    }
  }
}

String genAiStatusLabel(String status) => switch (status) {
      'available' => 'Hazır: grafik ve şekiller arka planda açıklanır.',
      'downloadable' => 'Bu cihaz destekliyor; model indirilmeli.',
      'downloading' => 'Model iniyor…',
      'unavailable' => 'Bu cihazda kullanılamıyor (Gemini Nano desteklenmiyor).',
      _ => 'Durum alınamadı: $status',
    };
