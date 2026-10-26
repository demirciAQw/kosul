/// ML Kit GenAI "Resim açıklaması" (Gemini Nano) için Android yamaları.
///
/// Flutter eklentisi olmadığı için uygulamaya küçük bir yerel köprü eklenir:
/// `kocum/genai` kanalı (status, download, describe). Fonksiyonlar saf metin
/// dönüşümleridir; test/genai_patch_test.dart ile denenir.
library;

const genAiDependency = 'com.google.mlkit:genai-image-description:1.0.0-beta1';

/// GenAI kütüphaneleri yeni Android ister; resmi örnekle aynı alt sınır.
const genAiMinSdk = 31;

/// app/build.gradle.kts: minSdk ve bağımlılık. Zaten yamalıysa dokunmaz.
String patchGenAiKts(String s) {
  if (s.contains(genAiDependency)) return s;
  s = s.replaceFirstMapped(
    RegExp(r'minSdk\s*=\s*[^\n]+'),
    (_) => 'minSdk = $genAiMinSdk',
  );
  return '$s\ndependencies {\n    implementation("$genAiDependency")\n}\n';
}

/// app/build.gradle (Groovy): minSdk ve bağımlılık.
String patchGenAiGroovy(String s) {
  if (s.contains(genAiDependency)) return s;
  s = s.replaceFirstMapped(
    RegExp(r'minSdk(Version)?\s*=?\s*[^\n]+'),
    (_) => 'minSdkVersion $genAiMinSdk',
  );
  return "$s\ndependencies {\n    implementation '$genAiDependency'\n}\n";
}

/// Üretilmiş MainActivity'nin paket adı ("package com.kocum.kocum").
String? packageOf(String mainActivity) => RegExp(r'^package\s+([\w.]+)', multiLine: true)
    .firstMatch(mainActivity)
    ?.group(1);

/// Kanal köprüsüyle MainActivity. Yalnızca resmi örnekte doğrulanan sınıflar
/// kullanılır; sonuç türleri içe aktarılmaz (çıkarım), böylece yanlış bir sınıf
/// adı derlemeyi bozmaz.
String genAiMainActivity(String package) => '''
package $package

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.imagedescription.ImageDescriber
import com.google.mlkit.genai.imagedescription.ImageDescriberOptions
import com.google.mlkit.genai.imagedescription.ImageDescription
import com.google.mlkit.genai.imagedescription.ImageDescriptionRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/// Koçum: ML Kit GenAI resim açıklaması (Gemini Nano, telefonda) köprüsü.
class MainActivity : FlutterActivity() {
    private var describer: ImageDescriber? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private fun client(): ImageDescriber =
        describer ?: ImageDescription.getClient(ImageDescriberOptions.builder(this).build()).also { describer = it }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kocum/genai").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> try {
                    val future = client().checkFeatureStatus()
                    future.addListener({
                        val name = try {
                            when (future.get()) {
                                FeatureStatus.AVAILABLE -> "available"
                                FeatureStatus.DOWNLOADABLE -> "downloadable"
                                FeatureStatus.DOWNLOADING -> "downloading"
                                FeatureStatus.UNAVAILABLE -> "unavailable"
                                else -> "unknown"
                            }
                        } catch (t: Throwable) {
                            "error: " + t.message
                        }
                        main.post { result.success(name) }
                    }, executor)
                } catch (t: Throwable) {
                    result.success("error: " + t.message)
                }
                "download" -> try {
                    var answered = false
                    fun answer(value: String) = main.post {
                        if (!answered) {
                            answered = true
                            result.success(value)
                        }
                    }
                    client().downloadFeature(object : DownloadCallback {
                        override fun onDownloadStarted(bytesToDownload: Long) {}
                        override fun onDownloadProgress(totalBytesDownloaded: Long) {}
                        override fun onDownloadCompleted() { answer("available") }
                        override fun onDownloadFailed(e: GenAiException) { answer("error: " + e.message) }
                    })
                } catch (t: Throwable) {
                    result.success("error: " + t.message)
                }
                "describe" -> {
                    val path = call.argument<String>("path")
                    executor.execute {
                        try {
                            val bitmap = BitmapFactory.decodeFile(path)
                            if (bitmap == null) {
                                main.post { result.error("decode", "Görüntü açılamadı", null) }
                            } else {
                                val future = client().runInference(ImageDescriptionRequest.builder(bitmap).build())
                                future.addListener({
                                    try {
                                        val text = future.get().description
                                        main.post { result.success(text) }
                                    } catch (t: Throwable) {
                                        main.post { result.error("genai", t.message, null) }
                                    }
                                }, executor)
                            }
                        } catch (t: Throwable) {
                            main.post { result.error("genai", t.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        describer?.close()
        executor.shutdown()
        super.onDestroy()
    }
}
''';
