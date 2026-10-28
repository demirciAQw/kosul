# Koçum: proje notları (Claude Code için)

YKS'ye hazırlanan bir öğrencinin kişisel çalışma uygulaması. Flutter, Android.
Veriler yalnızca telefonda (sunucu yok). Arayüz, yorumlar ve commit mesajları
**Türkçe**. Kullanıcı (geliştirici aynı zamanda öğrenci) kısa, sade Türkçe ister.

**Sıradaki büyük iş:** tablet + PDF modu. Ayrıntılı tarif:
[`docs/TABLET_PDF.md`](docs/TABLET_PDF.md). Telefon akışı bozulmadan eklenir.

## Mimari

- Riverpod (durum), Drift/SQLite (veritabanı), go_router (gezinme).
- Özellik klasörleri `lib/features/<özellik>/{domain,data,presentation}`.
  Domain saf Dart: test edilebilir, Flutter'a bağlı değil.
- Ortak: `lib/core/` (database, media, export, text, notifications, di).
- Önemli yerler:
  - `core/database/` tablolar ve göçler (`schemaVersion` şu an 11)
  - `features/question_bank/` soru kartları, defter, optik, akıllı arama
  - `features/ocr/` fotoğraftan okuma (ML Kit), sayfa okuyucu
    (`domain/reader/page_reader.dart`: soru, kök, öncül, şık; konuma göre),
    şekil bulucu (`figure_detector.dart`), otomatik etiket (`auto_tags.dart`,
    sözlük `assets/meb/konu_sozlugu.json`)
  - `features/dashboard/` derin analiz, soru kökü analizi, Claude raporu
  - `features/library/` kitaplar ve kitap haritası (şablonlar `assets/templates/`)
  - `features/mock_exam/` denemeler, karne PDF içe aktarma
  - `core/media/` fotoğraf akışı: çekim, kırpma, arka planda sıkıştırma,
    uygulama içi hızlı kamera (performans modu)
- Android projesi depoda **yok**; derlemede `flutter create` ile üretilir ve
  `tool/patch_android.dart` ile ayarlanır (imza, R8 kuralları, izinler, GenAI
  köprüsü). Android'e ait her değişiklik bu betikten yapılır, testli saf
  fonksiyonlar `tool/*_patch.dart` içinde.

## Komutlar

```bash
flutter pub get
# Android iskeleti yoksa (bir kez):
flutter create --org com.kocum --project-name kocum --platforms android /tmp/iskelet
cp -r /tmp/iskelet/android ./android
dart tool/patch_android.dart
dart run build_runner build --delete-conflicting-outputs   # Drift kodu
flutter analyze
flutter test                                              # derlemeyi kapılar
flutter build apk --release --target-platform android-arm64
```

CI (`.github/workflows`) aynı adımları izler; **testler geçmezse APK üretilmez**.

## Kurallar

- Her özellik testle gelir; domain mantığı saf fonksiyonlarda.
- Değişiklikten sonra `flutter analyze` ve `flutter test` temiz olmalı.
- Sürüm: `pubspec.yaml` `version` artırılır; commit mesajı sürüm notudur
  (ör. `v8.2: …` ve altında maddeler).
- Veritabanı göçü: `schemaVersion` artır; eski sürümden gelen her yol düşünülür
  (ör. tablo `from < 10`'da yeni sütunlarla oluşur, sütun ekleme yalnızca
  `from == 10` için).
- Türkçe metin karşılaştırma ve arama için `core/text/turkish_text.dart`
  (`normalizeTr`, `titleCaseTr`); `toLowerCase()` "İ" için yanlış sonuç verir.
- Kullanıcı verisi asla sessizce silinmez; geçici dosyalar iş bitince silinir.
- Yeni bağımlılıklarda lisans kontrolü: MIT/BSD/Apache uygun; **GPL kod
  alınmaz** (ör. Saber uygulaması GPL; yalnızca fikir alınabilir).
- Uygulama boyutu önemli: model dosyası gömmekten kaçın.

## Bu projede yaşanmış tuzaklar

- `var y = math.max(0, …)` `num` çıkarabilir; tamsayı bağlamında
  `math.max<int>` / `math.min<int>` yaz.
- Koleksiyonlarda `?ifade` (null-aware element) yazımı kullanılmaz;
  `[a, b].whereType<T>()` ya da `if (x != null) x` kullan.
- Chip yazı rengi: `labelStyle` için durum stili değil, durum rengi
  (`WidgetStateColor`) ver; yoksa açık temada yazı kaybolur.
- R8: ML Kit bileşenleri yansıma ile bulunur; `tool/r8_patch.dart` koruma
  kurallarını yazar. Yeni ML Kit paketi eklenirse kurala eklenmeli.
- Dart `'''` dizgesi ilk boş satırı atar (şablon testlerinde dikkat).
- `Navigator.push` ile açılmış bir ekranın üstüne go_router sayfası itme;
  altında kalabilir. Optik gibi zorunlu ekranlarda `Navigator` kullan.
- Ekranda gezinme olmadan sağlayıcı izleyen kodda `ref.listenManual`
  ilk değeri kaçırabilir; gerekirse `fireImmediately: true`.

## Telefon uygulamasında olanlar (korunmalı)

Kitap haritası ve test bazlı optik; deneme ve karne PDF içe aktarma; yanlış
defteri (galeri/gruplu, akıllı arama, geçmiş); tekrar (aralıklı, benzer hatalar
öne); fotoğraftan okuma (yön, sütun, soru blokları, şıklar, şekil/grafik/
fotoğraf bölgeleri); otomatik konu ve soru türü etiketi; soru kökü analizi;
derin analiz; Claude raporu ve paketleri; dışa aktarma (PDF, xlsx, ZIP, yedek);
notlar; hatırlatıcılar; hızlı kamera; Gemini Nano köprüsü (cihaz desteklerse).
