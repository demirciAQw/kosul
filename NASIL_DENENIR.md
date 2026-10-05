# Koçum'u telefonunda deneme

Uygulama Flutter ile yazıldı. Telefonda çalışması için önce bir APK'ya (Android uygulama dosyası) çevrilmesi gerekiyor. İki yol var; kolay olanı birincisi.

## Yol 1: Bilgisayara hiçbir şey kurmadan (GitHub ile, yaklaşık 15 dk)

GitHub, APK'yı senin yerine bulutta derler.

1. github.com'da ücretsiz hesap aç, **New repository** de (Private seçebilirsin).
2. **uploading an existing file** bağlantısına tıkla. Bu klasörün **içindeki** her şeyi (klasörün kendisini değil) sürükle bırak, **Commit changes** de.
   - Mac'te `.github` klasörü gizli görünür: Finder'da `Cmd + Shift + .` ile göster.
3. **Actions** sekmesinde "APK derle" görünmüyorsa: **Add file → Create new file**, dosya adına `.github/workflows/build-apk.yml` yaz, `ci/build-apk.yml` dosyasının içeriğini yapıştır, commit et.
4. **Actions → APK derle → Run workflow**. 10-15 dk sürer.
5. Yeşil tik çıkınca işlemin sayfasında en altta **Artifacts → kocum-apk** dosyasını indir, zip'i aç: `app-release.apk`.
6. APK'yı telefona gönder (Telegram, Drive, USB). Dokun, "bilinmeyen kaynaklardan yükle" iznini ver. HyperOS bir güvenlik taraması gösterirse "Yine de yükle" de.

## Yol 2: Bilgisayarda Flutter ile (kablolu)

1. Flutter'ı kur: flutter.dev → Install → Android. Android Studio de gerekir. Sonra `flutter doctor` komutunda Android satırı yeşil olmalı.
2. Bu klasörde:
   - Windows: `tool\setup.bat`
   - Mac / Linux: `./tool/setup.sh`
3. Redmi'de **Ayarlar → Telefon hakkında** bölümünde HyperOS sürümüne 7 kez dokun. Sonra **Ek ayarlar → Geliştirici seçenekleri**ten **USB hata ayıklama** ve **USB üzerinden yükle** seçeneklerini aç.
4. Telefonu USB ile bağla, bilgisayara izin ver, sonra: `flutter run --release`

## İlk açılışta ne denemeli? (3 dk)

1. **Bugün** sekmesinde **Örnek kitabı ekle** (345 TYT Matematik hazır gelir).
2. **Yeni oturum**: birkaç konu ya da tek tek sayfa işaretle, **BAŞLA**. Uygulamayı kapatıp aç: süre işlemeye devam eder. Bildirim çubuğunda canlı sayaç görürsün. Sonra **Bitir**.
3. **Eksiklerini doldur** rozeti çıkar. Doğru / yanlış / boş gir ya da **Sonra** de.
4. Sonuç ekranında **Yanlış ya da boş soru ekle**: fotoğraf çek, kırp, doğru çözümü ekle, sağ üstten yıldızla.
5. **Defter** sekmesi: ara, filtrele, Ders / Kitap / Konu diye grupla.
6. **Plan** sekmesi: tarih aralığı seç, görev havuzu oluştur, görevden oturum başlat.
7. **Analiz** sekmesi: en çok yanlış yaptığın konu / neden ve tahmini kayıp süre.

Not: Yeni eklenen yanlışlar **ertesi gün** tekrar listesine (Yanlışlarımı göster) düşer. İlk gün "bugün tekrar yok" görmen normaldir.

## Hata alırsan

Bu kodu yazarken Flutter'ı çalıştıramadım, yani ilk derlemede küçük bir hata çıkabilir.

- GitHub'da kırmızı çarpı çıkarsa: o işleme tıkla, kırmızı adıma tıkla, hata satırlarını kopyala.
- Bilgisayarda bir komut hata verirse: ekrandaki hatayı kopyala.

Hatayı bana yapıştır, düzeltip yeni sürümü veririm.
