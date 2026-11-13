# Koçum: proje notları (Claude Code için)

YKS'ye hazırlanan bir öğrencinin kişisel çalışma uygulaması. Flutter, Android.
Veriler telefonda; internete çıkmaz. Eşlenirse yedek yerel ağda bilgisayardaki
`koc sunucu`ya (`~/koc-arac`, Python) gider. Arayüz, yorumlar ve commit mesajları
**Türkçe**. Kullanıcı (geliştirici aynı zamanda öğrenci) kısa, sade Türkçe ister.

**Sıradaki iş (sırayla):** v8.5 koç klasörü, sonra v8.6–v9.0 Anlık, grafik, eşitleme, öneriler,
dinamik program. Hepsi tek belgede: [`docs/ANLIK.md`](docs/ANLIK.md).
Bir sürüm bitmeden diğerine geçme.

**Daha sonraki büyük iş:** tablet + PDF modu. Ayrıntılı tarif:
[`docs/TABLET_PDF.md`](docs/TABLET_PDF.md). Telefon akışı bozulmadan eklenir.
Aynı belgede **I. Benzer sorularda gelişim** ("bu hatayı öğrendim mi?") hem
telefon (konu düzeyi) hem tablet (soru düzeyi) için tarif edilmiştir.

## Mimari

- Riverpod (durum), Drift/SQLite (veritabanı), go_router (gezinme).
- Özellik klasörleri `lib/features/<özellik>/{domain,data,presentation}`.
  Domain saf Dart: test edilebilir, Flutter'a bağlı değil.
- Ortak: `lib/core/` (database, media, export, text, notifications, di).
- Önemli yerler:
  - `core/database/` tablolar ve göçler (`schemaVersion` şu an 12)
  - `features/question_bank/` soru kartları, defter, optik, akıllı arama
  - `features/ocr/` fotoğraftan okuma (ML Kit), sayfa okuyucu
    (`domain/reader/page_reader.dart`: soru, kök, öncül, şık; konuma göre),
    şekil bulucu (`figure_detector.dart`), otomatik etiket (`auto_tags.dart`,
    sözlük `assets/meb/konu_sozlugu.json`)
  - `features/dashboard/` derin analiz, soru kökü analizi, Claude raporu
  - `features/library/` kitaplar ve kitap haritası (şablonlar `assets/templates/`)
  - `features/mock_exam/` denemeler, karne PDF içe aktarma
  - `features/sync/` bilgisayarla eşleme ve eşitleme (v8.5): kurallar
    `domain/koc_baglantisi.dart`, istemci/bulucu/eşitleyici `data/`. Karşı
    taraf `~/koc-arac/koc/sunucu.py`; istek alan adları iki tarafta aynı.
  - `features/anlik/` Anlık (v8.6): kısa notlar, `((etiket))`, etiket şeridi,
    alt-üst etiketler. Kurallar `domain/etiket_metni.dart` ve
    `domain/etiket_kurallari.dart`; veritabanı `data/anlik_deposu.dart` (eşitleme kaynağı).
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
notlar; hatırlatıcılar; hızlı kamera; Gemini Nano köprüsü (cihaz desteklerse);
bilgisayarla eşleme ve otomatik yedek (v8.5); Anlık ve etiketler (v8.6).
