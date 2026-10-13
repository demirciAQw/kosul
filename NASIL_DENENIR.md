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

## Sabit imza (bir kez yapılır, sonra hiç kaldır-yükle yok)

Her derleme farklı bir anahtarla imzalanırsa Android yeni sürümü eskisinin üstüne kurmaz; eskisini kaldırmak gerekir ve **defterdeki tüm veriler silinir**. Sabit imzayla güncellemeler üstüne kurulur, veriler kalır.

1. Sana verilen `imza.env` dosyasını proje klasörünün **dışında** bir yere koy (depo herkese açık; bu dosya ASLA depoya girmemeli).
2. Terminalde: `gh secret set -f imza.env --repo demirciAQw/kosul`
   - Ya da GitHub'da **Settings → Secrets and variables → Actions → New repository secret** ile iki sır ekle: `KEYSTORE_BASE64` ve `KEYSTORE_PASSWORD` (değerler `imza.env` içinde).
3. `kocum-release.jks` ve `imza.env` dosyalarını Drive gibi güvenli bir yerde sakla. Kaybolursa yeni anahtara geçmek için bir kez daha kaldır-yükle gerekir.

Sırlar eklendikten sonraki ilk APK'yı kurmadan önce eski (farklı imzalı) sürümü **son kez** kaldır. Ondan sonraki her APK doğrudan üstüne kurulur.

Actions kaydında "Sabit imza kullaniliyor." satırını görürsen imza çalışıyor demektir.

## Yol 2: Bilgisayarda Flutter ile (kablolu)

1. Flutter'ı kur: flutter.dev → Install → Android. Android Studio de gerekir. Sonra `flutter doctor` komutunda Android satırı yeşil olmalı.
2. Bu klasörde:
   - Windows: `tool\setup.bat`
   - Mac / Linux: `./tool/setup.sh`
3. Redmi'de **Ayarlar → Telefon hakkında** bölümünde HyperOS sürümüne 7 kez dokun. Sonra **Ek ayarlar → Geliştirici seçenekleri**ten **USB hata ayıklama** ve **USB üzerinden yükle** seçeneklerini aç.
4. Telefonu USB ile bağla, bilgisayara izin ver, sonra: `flutter run --release`

## İlk açılışta ne denemeli? (5 dk)

1. **Bugün → Hazır kitap ekle**: Sıfır Risk Paragraf ve Aydın 11. Sınıf Kimya'yı **Ekle** ile kitaplığına al.
2. **Yeni oturum → Kitaptan**: birkaç konu ya da tek tek sayfa işaretle, **BAŞLA**. Uygulamayı kapatıp aç: süre işlemeye devam eder. Yanlışlıkla başlattıysan **İptal et**.
3. Oturum sürerken bir bölümün yanındaki işaret simgesiyle **optik formu** aç: yanlış numaralarına dokun, **Kaydet**. Sonra **Bitir**.
4. Sonuç ekranında sayılar dolu gelir. **Yanlışları işaretle** ile değiştirebilir, **Fotoğraflı** ile tam kayıt ekleyebilirsin.
5. **Defter → Eksikler**: optikten gelen soruların satırından tek dokunuşla neden ve fotoğraf ekle. Fotoğrafta köşeleri sürükleyerek kırp, gerekirse döndür.
6. **Yeni oturum → Kitapsız**: ders seç, "Video" ya da "Konu çalışması" de, başlat. Bitirince sonuç sorulmaz.
7. **Deneme** sekmesi: **Deneme ekle**, ders ders doğru ve yanlışı yaz; boş ve net kendiliğinden çıkar. Deneme sayfasında bir dersin **Yanlışları işaretle** düğmesiyle soruları deftere at.
8. **Kitaplar** sekmesi: kitaba dokun, kitap haritasını gör; bir testi kutucukla çözüldü yap; teste dokun → **Optikle işaretle**, işaretli numaraya dokununca soru açılır.
9. Paragraf kitabından bir **ünitenin tamamını** seçip oturum başlat, bitince **Yanlışları işaretle**: form test test bölünmüş olmalı. Bir testi "Çözdüm" anahtarıyla kapat; kaydedince kitap haritasında yalnızca çözdüklerin işaretli olmalı.
10. **Defter → Soru ekle → Kitap**: sadece kitap, test ve soru no sorulmalı. **Diğer** nedenini seçince açıklama alanı çıkmalı. Defterde bir soruya uzun bas, birkaç tane seç, sil.
11. **Bugün → Geçmiş oturumlar**: bir oturumun süresini düzelt, sonuçlarını düzenle, sil.
12. **Bugün → Planlarım**: **Yeni plan → Haftalık**, görev ekle ya da eklemeden oluştur; vazgeçmek için **Vazgeç**. Plan kartında **Tamamladım**, **Görev ekle** ve **Sil** (geri alınabilir); görevi silmek için sola kaydır.
13. **Analiz** sekmesi: derslere göre örüntüler (en az 3 yanlış biriktiğinde), en çok yanlış yaptığın konu / neden ve tahmini kayıp süre.

Not: Yeni eklenen yanlışlar **ertesi gün** tekrar listesine (Yanlışlarımı göster) düşer. İlk gün "bugün tekrar yok" görmen normaldir.

## Hata alırsan

Bu kodu yazarken Flutter'ı çalıştıramadım, yani ilk derlemede küçük bir hata çıkabilir.

- GitHub'da kırmızı çarpı çıkarsa: o işleme tıkla, kırmızı adıma tıkla, hata satırlarını kopyala.
- Bilgisayarda bir komut hata verirse: ekrandaki hatayı kopyala.

Hatayı bana yapıştır, düzeltip yeni sürümü veririm.
