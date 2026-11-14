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
13. **Deneme → üstteki yükleme simgesi**: okul karnesi PDF'ini seç. Önizlemede netler, puan ve deftere eklenecek yanlışlar görünür; **Kaydet**. Deneme sayfasında Kimya'nın optiği 8–14 numaralarıyla açılmalı; defterde yanlışlar kazanım adıyla durmalı. Aynı karneyi tekrar yüklersen "zaten kayıtlı" diye sorar.
14. **Analiz** sekmesi: derslere göre örüntüler (en az 3 yanlış biriktiğinde), en çok yanlış yaptığın konu / neden ve tahmini kayıp süre.

Not: Yeni eklenen yanlışlar **ertesi gün** tekrar listesine (Yanlışlarımı göster) düşer. İlk gün "bugün tekrar yok" görmen normaldir.

## Bilgisayarla eşleme (v8.5)

Telefon aynı Wi-Fi'deyken yedeğini (fotoğrafsız) bilgisayara kendiliğinden gönderir. İnternet kullanılmaz.

1. Bilgisayarda (bir kez, ufw açıksa): `sudo ufw allow from 192.168.0.0/16 to any port 8765 proto tcp`
   ve `sudo ufw allow from 192.168.0.0/16 to any port 5353 proto udp`
2. Bilgisayarda: `cd ~/koc-arac && uv run koc sunucu`
3. Telefonda: **Ayarlar > Bilgisayarla eşle**. Bilgisayar listede çıkar (çıkmazsa sunucunun yazdığı IP'yi elle yaz).
4. Bilgisayara dokun; terminalde 6 haneli kod çıkar. Kodu telefona yaz, **Eşle** de.
5. Birkaç saniye sonra terminalde "eşitlendi, yedek alındı" yazar; yedek `~/koc-arac/veri/kocum_yedek.json`.
6. Uygulamayı kapatıp aç ya da bir oturum bitir: terminalde yeni satır çıkar ("yedek aynı" ya da "yedek alındı").
   Aynı dakikada iki kez açarsan ikincisi beklenir (en fazla 2 dakikada bir).
7. **Eşlemeyi kaldır** de: terminalde "Eşleme kaldırıldı" yazar.

## Anlık (v8.6)

1. **Bugün** ekranında üstteki kalem simgesi: Anlık açılır (alt sekme yok).
2. Aşağıya `bugün ((garson)) çağıramadım` yaz. `((` yazınca öneri listesi açılır; sonda **Yeni etiket: garson** çıkar.
   Dokun: pencerede ad, tür (Kişi/Duygu/...), üst etiket ve renk; **Oluştur**. Metindeki `((garson))` renklenir.
3. **His**'e dokun, -2 seç, gönder. Anlık listede "Bugün" başlığı altında, üstünde çerçeveli **garson** çipiyle görünür.
4. Yazma alanındaki **+ Etiket**: arama kutulu ağaç listesi açılır; birkaç etiket işaretle, **Ekle**. Gönder.
   Bu çiplerin × düğmesi çalışır; metinden gelen çipin ×'i "metinden sil" der.
5. Bir çipe dokun: etiket sayfası (o etiketli anlıklar). Sağ üst menü **Etiketi sil**: sayılar ve seçenekler görünür.
   Silince metindeki `((garson))` düz yazıya döner; Anlık menüsü **Son silinen etiketler**'den **Geri al**.
6. Bir anlığa dokun: düzenle ya da sil.
7. Sol üstteki ızgara simgesi ana uygulamaya döner. Uygulamayı Anlık'ta kapatırsan bir dahaki açılışta Anlık açılır.
8. Uygulama simgesine uzun bas: **Anlık yaz** kısayolu yazma alanı açık gelir.
9. **Ayarlar > Obsidian anlarını içe aktar**: `Anlar/*.md` dosyalarını seç. İkinci kez seçersen "atlandı" der.
10. Eşliyse: anlık yazınca bilgisayara gider (`koc sunucu` terminalinde "eşitlendi").

### Etiket etiketi ve arama (v8.6.1)

1. Bir etiket çipine **uzun bas**: menü açılır.
2. **Etiket etiketi ekle**: listeden `tiksinti` seç (yoksa yaz, "tiksinti ekle"), **Ekle**. Artık `tiksinti`, `his`'in altında.
3. `tiksinti`'ye uzun bas > **Etiket etiketi ekle** > `his`: "döngü olurdu" der, eklenmez.
4. **Yeniden adlandır**: önce "N anlık etkilenecek" yazar; metinlerdeki `((eski))` yeni adla değişir.
5. **Birleştir**: iki etiketten biri diğerine katılır; anlıklar ve alt etiketler geçer.
6. Arama kutusuna `#his` yaz: `his` ve altındaki `tiksinti` etiketli anlıklar gelir. `-#ders` dışlar. `((his))` de olur.
7. Süz simgesi: Etiket (Hepsi/Herhangi biri), Tarih, Duygu, Metin içi/Şerit/Yapay zekâ, Etiketsiz çipleri. **Temizle**.
8. Yanlış defterindeki arama eskisi gibi çalışmalı (yazım hatası toleransı aynı).

## Noktasal grafik (v8.7)

1. Anlık'ta sağ üstteki baloncuk simgesi: grafik bütün anlıklarla açılır. Eskiler dışta ve solda, yeniler içte ve sağda.
2. İki parmakla yakınlaştır. Bir noktaya dokun: anlık açılır; etikete dokun: etiket sayfası.
3. Etikete uzun bas: sadece komşuları parlak kalır. Boş yere dokun: hepsi geri gelir.
4. Alttaki **Düzen ↔ Bağ** kaydırıcısı: solda tarih sarmalı korunur, sağda bağlar şekli toplar.
5. Üstteki seçici: **Takvim** (her gün bir nokta, her tur bir hafta, hafta başları "9–15 Kas" gibi yazılı),
   **Metin içi**, **Ana etiketler** (artılı etikete dokun: altları açılır), **Etiket ağacı**.
6. Geri çık, grafiği yeniden aç: seçtiğin görünüm ve kaydırıcı yeri hatırlanır.
7. Arama kutusuna `#his` yaz, **Grafikte göster**: grafik sadece bu sonuçlarla açılır; Takvim'de bu anlıklar mavi.

## Hata alırsan

Bu kodu yazarken Flutter'ı çalıştıramadım, yani ilk derlemede küçük bir hata çıkabilir.

- GitHub'da kırmızı çarpı çıkarsa: o işleme tıkla, kırmızı adıma tıkla, hata satırlarını kopyala.
- Bilgisayarda bir komut hata verirse: ekrandaki hatayı kopyala.

Hatayı bana yapıştır, düzeltip yeni sürümü veririm.
