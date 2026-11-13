# Koçum yol haritası: v8.5 – v9.0

Bu belge Claude Code için bir yol haritasıdır. Her sürüm ayrı bir dalda, ayrı bir iş olarak yapılır.
Bir sürüm bitmeden diğerine geçilmez. Her sürümün sonunda dur ve kullanıcıya 5 satırlık özet ile
"önce şu dosyayı oku" önerisi ver. Kullanıcı kodu okuyup anlamak istiyor: sade yaz, her yeni dosyanın
başına ne yaptığını anlatan 3–5 satır koy.

İlk iş v8.5'tir (aşağıda). **Merkez bilgisayardır:** `koc-arac` içindeki `koc sunucu` yerel ağda çalışır,
telefon (ve v8.8'den sonra Linux masaüstü uygulaması) ona bağlanır. Syncthing ya da bulut kullanılmaz.

## Temel ilkeler (bütün sürümler)
1. **Modüler:** Yeni özellikler `lib/features/anlik/`, `lib/features/sync/`, `lib/features/oneriler/`
   klasörlerine gider. Domain saf Dart, testli.
2. **Eşitlenecek her kayıt** `guncelleme` (zaman), `silindi` (yumuşak silme) ve `esitlenmedi`
   (son eşitlemeden beri değişti mi) alanlarını taşır. v8.6'dan itibaren her yeni tablo bu kurala uyar;
   sonradan eklemek göç derdi çıkarır.
3. **Yapay zekâ doğrudan veriye yazmaz.** Her değişikliği bir **öneri paketi** olarak yazar, kullanıcı
   uygulamada onaylar (v8.9). Kod (benzerlik, program hesabı) da öneri üretir, onaysız uygulamaz.
4. **Hesap kodda, yorum yapay zekâda.** Program, bağ puanları ve sapmalar Dart ya da Python kodunda
   hesaplanır. Claude sadece yorum yapar ve hedef önerir.
5. Telefon akışı bozulmaz. Mevcut "Defter" (ders notları, `StudyNotes`) olduğu gibi kalır; Anlık ayrı bir şeydir.

---

## v8.5: Bilgisayarla eşleme ve otomatik yedek

Telefon ve bilgisayar aynı Wi-Fi'deyken doğrudan konuşur, internet kullanılmaz. Bu bölüm iki taraflıdır:
sunucu `koc-arac` deposunda (Python), istemci burada (Flutter). `koc-arac/CLAUDE.md` bu belgeye bakar.
**v8.5'te sadece `kocum.backup` gönderilir.** Anlık, etiket ve bağ alanları v8.6'da aynı isteğe eklenir;
aşağıdaki çakışma kuralı onlar için de geçerlidir.

### Bulma ve eşleme
- Bilgisayarda `koc sunucu` yerel ağda bir HTTP sunucusu açar (varsayılan port 8765) ve kendini
  mDNS ile `_koc._tcp` olarak duyurur.
- Telefon Ayarlar > "Bilgisayarla eşle" ekranında koçu bulur. Bulamazsa IP elle yazılabilir.
- Bilgisayar terminalde 6 haneli bir kod gösterir; kullanıcı kodu telefona yazar. Kod 5 dakika geçerli.
- Eşleşince bilgisayar uzun bir **anahtar** verir; telefon bunu güvenli depoda saklar ve sonraki her
  istekte gönderir. Anahtarsız istek reddedilir.
- Sunucu sadece özel ağ adreslerinden (192.168.x, 10.x, 172.16–31.x) gelen isteklere cevap verir.
- Ayarlardan "Eşlemeyi kaldır" denebilir (iki tarafta da anahtar silinir).

### Eşitleme (`POST /esitle`)
Telefon gönderir:
- `sonEsitleme`: bir önceki başarılı eşitlemenin sunucu zamanı (ilk seferde null),
- (v8.6'dan itibaren) `esitlenmedi` işaretli `anliklar`, `etiketler`, `baglar` (silinenler `silindi: true`),
- tam `kocum.backup` JSON'u (**fotoğrafsız**). Değişmediyse içeriğin özeti (hash) gönderilir, JSON gönderilmez.

Bilgisayar cevap verir:
- kendi tarafında o zamandan beri değişenleri (masaüstünde yazılan anlıklar, onaylanan öneriler),
- (v8.9'dan itibaren) bekleyen öneri paketlerini,
- yeni `sunucuZamani`.

**Çakışma:** Aynı anlık son eşitlemeden beri iki tarafta da değiştiyse telefondaki sürüm kalır,
bilgisayardaki sürüm yeni kimlikle ayrı bir anlık olarak saklanır ve başına `(çakışma kopyası)` yazılır.
Hiçbir veri sessizce kaybolmaz. Etiket adı çakışmasında aynı normalize ada sahip etiketler birleştirilir.

Her kayıt `guncelleme` zaman damgası taşır. Silme kalıcı silme değildir, `silindi: true` olarak gider.
30 gün sonra iki taraf da silinmişleri temizleyebilir.

### Otomatik eşitleme
Telefon uygulama açılınca, bir çalışma oturumu bitince ve Anlık kaydedilince (en fazla 2 dakikada bir)
eşitlemeyi dener. Koç bulunamazsa sessizce vazgeçer; Ayarlarda son başarılı eşitleme zamanı görünür.

### Testler
- Çakışma kuralı, silinenler ve "değişenleri seç" mantığı iki tarafta da saf fonksiyon olarak test edilir.
- `koc-arac` içinde sahte bir telefon istemcisiyle uçtan uca test yazılır.

---

## v8.6: Anlık (veri, yazma, etiketler, sade arayüz)

İki parçada yapılır, her parçanın sonunda dur:
- **v8.6.0:** Veri, sade arayüz ve geçiş, yazma, `((…))`, etiket şeridi, yeni etiket penceresi, etiket silme, içe aktarma.
- **v8.6.1:** Etiket etiketi (alt-üst) ve arama.

### Veri (schemaVersion 12)
```
Anliklar   id, metin, olusturma, guncelleme, duygu (int? -3..+3), cihaz, silindi
Etiketler  id, ad, normAd (normalizeTr, benzersiz), tur (kisi|duygu|konu|yer|diger),
           renk (int?), olusturan (ben|ai), olusturma, silindi
Baglar     id, tip (etiketli|ust|ilgili), kaynakTur (anlik|etiket), kaynakId, hedefTur, hedefId,
           neden (metin|serit|elle|ai), durum (onerildi|onayli|reddedildi), puan (real?), olusturma, silindi
Ayarlar    (mevcut ayarlar bu tabloya taşınmaz; v8.8'de eşitlenecek ayarlar için anahtar/değer + saat)
```
- `etiketli`: anlık → etiket (`neden=metin` metindeki `((…))`, `neden=serit` etiket şeridinden).
- `ust`: etiket → üst etiket (`tiksinti` → `his`). Bir etiketin birden çok üstü olabilir.
- `ilgili`: anlık ↔ anlık.
- Silme yumuşaktır (`silindi`); veri asla sessizce kaybolmaz.
- Her tabloda ayrıca `guncelleme` ve `esitlenmedi` vardır (Temel ilke 2).

### Metin içi etiket: `((etiket))`
- Metinde `((selam))` "selam" etiketine bağdır. Kayıtta metin ayrıştırılır, `neden=metin` bağları
  yeniden hesaplanır (şerit, elle ve ai bağlarına dokunulmaz).
- `((` yazınca imlecin altında öneri listesi açılır: önce son 7 günde kullanılanlar, sonra en çok
  kullanılanlar. Yazdıkça süzülür (`normalizeTr`). Listenin sonunda "Yeni etiket: …" seçeneği olur.
- Yazarken `((…))` kısmı renkli görünür; dokununca etiketin sayfası açılır.

### Yeni etiket penceresi (her yoldan aynı pencere)
Etiket oluşturulmadan önce alttan bir pencere açılır: **ad** (yazılan kelimeyle dolu, düzenlenebilir),
**tür**, isteğe bağlı **üst etiket** ve **renk**. Kullanıcı "Oluştur" demeden etiket oluşmaz.
Vazgeçerse metindeki `((…))` düz yazı olarak kalır.

### Etiket şeridi (metnin dışında etiket)
- Her anlığın üstünde (yazma alanında da) bir **etiket şeridi** vardır: etiketler çip halinde, en sonda `+`.
  Böylece anlık kaydedilmeden önce de etiket eklenebilir.
- `+` basınca alttan arama kutulu bir liste açılır. Etiketler **ağaç halinde** görünür: üst etiketler
  başlık, altları girintili (ör. **his** altında tiksinti, utanç, mutluluk). Liste kapanmadan
  **birden çok** etiket işaretlenir, "Ekle" ile hepsi eklenir. Aranan ad yoksa en altta
  "**his ekle**" gibi bir satır çıkar ve yeni etiket penceresi açılır.
- Metindeki `((…))` etiketleri de şeritte görünür ama çerçevelidir ve şeritten kaldırılamaz
  ("Bu etiket metinde geçiyor, metinden sil"). Metinden silinince kendiliğinden kalkar.
- Çipteki `×` etiketi **o anlıktan** kaldırır (bağ yumuşak silinir, etiket kalır).
- Çipe dokununca etiket sayfası açılır: o etiketi (ve alt etiketlerini) taşıyan anlıklar, tarih sırasıyla.

### Etiket etiketi (alt-üst) — v8.6.1
- Bir etikete (şeritte, listede ya da etiket sayfasında) **uzun basınca** menü açılır:
  - **Etiket etiketi ekle:** Aynı `+` listesi açılır, seçilen ya da yeni oluşturulan etiket bu etiketin
    **altına** girer (`tip=ust`). Örnek: `his`'e uzun bas, "Etiket etiketi ekle", `tiksinti`.
  - **Üst etiket ekle:** Ters yön.
  - **Yeniden adlandır:** Metindeki `((eski))` yazıları da güncellenir; önce "N anlık etkilenecek" gösterilir.
  - **Birleştir:** İki etiketi tek etikette toplar.
  - **Sil** (aşağıda).
- **Ana etiket** = üstü olmayan etiket. Döngü (`his` → `tiksinti` → `his`) engellenir ve söylenir (test şart).
- Üst etiketle yapılan arama alt etiketlileri de getirir.

### Etiket silme
- Etiket sayfasından ya da uzun basma menüsünden. Önce sayı gösterilir: "his 14 anlıkta, 3 alt etikette."
- Seçenekler: (a) sadece bu etiketi sil, alt etiketler üst düzeye çıkar; (b) alt etiketleriyle sil.
- Anlıklar silinmez. Metindeki `((his))` düz yazıya döner. "Son silinenler"den 30 gün boyunca geri alınır.

### Arama — v8.6.1
Soru defterindeki akıllı aramanın (`question_bank/domain/smart_search.dart`: `searchTokens`,
`editDistance`, yazım hatası toleransı) ortak parçaları `core/text/` altına taşınır, iki yerden kullanılır.
Soru araması aynı sonucu vermeye devam etmeli; mevcut testler geçmeli.
- Kutu metinde ve etiket adlarında arar. Ağırlıklar: etiket 1.0, metin 0.7.
- Filtre çipleri: etiket(ler) (hepsi / herhangi biri; alt etiketleri kapsar), tarih aralığı, duygu aralığı,
  etiketin geldiği yer (metin içi, şerit, yapay zekâ), etiketsiz olanlar.
- Kısa yazım: `#his` etiket filtresi ekler, `-#ders` dışlar, `((his))` da `#his` gibi çalışır.
- Sonuç ekranında "**Grafikte göster**" düğmesi grafiği sadece bu sonuçlarla açar (v8.7).
- Arama mantığı saf Dart ve testli.

### Sade arayüz ve geçiş
- Anlık kendi kabuğuna sahiptir: alt sekmeler yok; üstte arama, ortada tarihli liste, altta her zaman
  açık yazma alanı (üstünde etiket şeridi) ve sağ üstte grafik düğmesi (v8.7). Sade renkler, büyük yazı.
- **Geçiş:** Ana uygulamada üst çubuktaki bir düğme Anlık'a, Anlık'taki bir düğme ana uygulamaya geçer.
  Son açılan mod hatırlanır.
- **Hızlı yazma:** Android uygulama kısayolu ("Anlık yaz") doğrudan yazma alanını açar
  (`tool/patch_android.dart` üzerinden).
- Duygu isteğe bağlıdır: yazma alanının yanında -3…+3 seçici, boş bırakılabilir.

### İçe aktarma (küçük)
Ayarlar'dan seçilen bir klasördeki `Anlar/*.md` dosyaları (v8.6 gelene kadar Obsidian'da `((etiket))` ile yazılanlar)
Ayarlar'dan tek seferlik içe aktarılır. Ön bilgideki `zaman` tarih olur, metin ve `((…))` korunur.

### Testler
`((…))` ayrıştırıcı (iç içe, kapanmamış, boş parantez, Türkçe harfler), bağ yeniden hesaplama,
döngü engeli, silme seçenekleri, arama kısa yazımı, `esitlenmedi` işaretleme ve içe aktarma.

---

## v8.7: Noktasal grafik

### Ortak kurallar
- Grafik her zaman o anki **arama ve filtre sonucuyla** çizilir (filtre yoksa bütün anlıklar).
- Düğümler: anlıklar (küçük nokta), etiketler (büyük, türüne göre renkli), görünüme göre gün/hafta düğümleri.
  `onerildi` durumundaki bağlar kesikli ve soluk çizilir.
- **Başlangıç yerleşimi tarihe göre bir sarmaldır.** t ∈ [0,1] tarihteki sıra olsun. Açı soldan başlar,
  üstten geçerek sağa ilerler (θ = π − t·πk, k ≈ 1,5); yarıçap dıştan içe azalır: r = R·(1 − 0,75t).
  Yani eskiler dışta ve solda, yeniler içte ve sağda. Etiket düğümü bağlı anlıkların ortalamasından başlar.
- **Sonra kuvvet düzeni:** Bağlar çeker, düğümler iter, her anlık sarmal konumuna bir yayla bağlıdır.
  "Düzen ↔ Bağ" kaydırıcısı yay gücünü ayarlar: solda tarih düzeni korunur, sağda yeni bağlar şekli bozar.
- **Rastgelelik yok:** Aynı veri aynı şekli verir. Hesap isolate içinde, en fazla 300 adım, 2000 düğüme kadar akıcı.
- Dokunma: düğüm → anlık/etiket sayfası. İki parmakla yakınlaştırma. Etikete uzun basınca sadece komşuları vurgulanır.
- Çizim `CustomPainter` ile, grafik kütüphanesi eklenmez.

### Görünümler (üstteki seçici; seçim ve kaydırıcı hatırlanır)
1. **Bağlar** (varsayılan): anlıklar, bütün etiketler ve bağlar.
2. **Takvim:** Her gün bir düğüm. Günler sırayla birbirine bağlanır ve sarmalın her turu bir haftadır
   (7 gün = 360°, dıştan içe). Hafta başları daha büyük ve "11–17 Kas" gibi etiketli. Anlıklar kendi gününün
   çevresinde küçük noktalar. Gün düğümünün büyüklüğü o günkü anlık sayısı, rengi o günün ortalama duygusu
   (yoksa gri). Etiket düğümü yoktur; seçili etiketi taşıyan anlıklar renklenir.
3. **Metin içi:** Sadece `((…))` ile gelen bağlar.
4. **Ana etiketler:** Alt etiketler üstlerine katlanır (`tiksinti` → `his`); düğüm büyüklüğü toplam anlık
   sayısı. Ana etikete dokununca açılır, altları görünür.
5. **Etiket ağacı:** Sadece etiketler ve alt-üst ilişkileri, anlık yok.

Her görünüm `grafVerisi(gorunum, filtre, anliklar, etiketler, baglar) -> (dugumler, kenarlar, baslangicKonumlari)`
saf fonksiyonudur ve testlidir (ör. aynı girdi aynı konum; t=0 solda dışta; takvimde 7 gün sonra açı başa döner
ve yarıçap küçülür; ana etiketler görünümünde alt etiket düğümü yoktur).

---

## v8.8: Eşitlemenin genişlemesi ve Linux masaüstü

### Eşitlemeye eklenenler
v8.5'teki `POST /esitle` isteği genişler, yeni bağlantı yolu açılmaz:
- **Ayarlar:** Sadece açıkça işaretlenenler (ör. günlük hedef dakikası, program ayarları) eşitlenir.
  Kamera ve izin ayarları cihaza özeldir.
- **Düzen** (v8.9) ve **plan** (v9.0) kayıtları aynı kurala uyar (`guncelleme`, `silindi`, `esitlenmedi`).
- Ayarlar'da son eşitleme zamanı ve hata varsa kısa açıklaması görünür.

### Linux masaüstü derlemesi
- Aynı kod tabanı `flutter build linux` ile CachyOS'ta çalışır. Kamera, ML Kit ve Android köprüleri
  masaüstünde kapalıdır (koşullu içe aktarma; düğmeler gizlenir).
- Masaüstü uygulaması da bir istemcidir: `localhost` üzerinden aynı `koc sunucu`'ya bağlanır ve eşleme
  kodunu aynı şekilde ister. Böylece telefon ↔ sunucu ↔ masaüstü tek bir kurala göre eşitlenir.
- Masaüstünde Anlık, grafik, etiket ekleme, ayarlar, plan ve öneri kutusu tam çalışır.
- CI'ya Linux derleme işi eklenir; çıktı bir `.tar.gz`. Bilgisayardaki paketlere göre (GTK, `clang`,
  `ninja`, `cmake`) kurulum komutları `NASIL_DENENIR.md`'ye yazılır.

### Testler
Üç istemcili senaryo (telefon, masaüstü, sunucu): aynı kaydın iki istemcide değişmesi, silme ile
güncellemenin çakışması, aynı isteğin iki kez gelmesi (sonuç değişmemeli).

---

## v8.9: Öneri kutusu (yapay zekâ ve kod buradan değiştirir)

Öneri paketleri `koc-arac/oneriler/*.json` dosyalarında durur ve eşitleme cevabıyla uygulamaya gelir.
Onay ya da red kararı bir sonraki eşitlemede sunucuya döner. Paket biçimi:
```json
{
  "id": "2026-11-20-bag-1",
  "kaynak": "ai",
  "aciklama": "Aynı kişiden bahseden 3 anlık",
  "islemler": [
    {"tur": "bag_ekle", "kaynak": "anlik:..", "hedef": "anlik:..", "puan": 0.71, "neden": "ortak kişi + benzer metin"},
    {"tur": "etiket_ekle", "ad": "kantin", "tur_etiket": "yer"},
    {"tur": "ayar", "anahtar": "gunluk_hedef_dk", "deger": 180},
    {"tur": "duzen", "yol": "altSekmeler", "deger": ["home", "anlik", "notebook", "mock", "insights"]},
    {"tur": "plan", "veri": { "...": "v9.0 biçimi" }}
  ]
}
```
- Uygulamada "Öneriler" kutusu: her paket açıklaması ve değişikliklerin önce/sonra hali ile görünür.
  "Onayla", "Reddet" ya da tek tek seçip "Seçilenleri uygula" seçenekleri olur. Uygulanan değişiklikler normal kayıtlar gibi
  `esitlenmedi` işaretlenir ve geri eşitlenir. Reddedilenler de kaydedilir ki aynı öneri tekrar gelmesin.
- Bilinmeyen `tur` hata değildir: paket "bu sürüm anlamıyor" diye işaretlenir.

### Düzen dosyası (arayüzü yapay zekâ ile değiştirmek)
- Ana sayfadaki kartların sırası ve görünürlüğü, alt sekmelerin sırası ve görünürlüğü, Anlık'taki hızlı
  düğmeler ve tema rengi tek bir `Duzen` nesnesinden okunur ve eşitlenir.
- Sınır açıkça şudur: düzen **mevcut parçaları** taşır, gizler ve sıralar. Yeni ekran ya da yeni düğme
  işlevi kod gerektirir; o zaman kullanıcı bunu Claude Code'a söyler.

---

## v9.0: Dinamik çalışma programı

Mevcut `features/planning` (StudyPlans, PlanTasks, plan_import) genişletilir.

- **Hedef:** ne (kitap/test aralığı, konu ya da serbest iş), miktar (soru, test ya da dakika), son tarih, öncelik.
- **Program hesabı (saf Dart, testli):** Girdiler hedefler, günlük müsait dakika (gün gün ayarlanabilir),
  konu zorluğu (o konudaki yanlış oranı; veri azsa ders ortalaması) ve tempo (geçmişte soru başına geçen
  süre; veri azsa ayarlardaki varsayılan). Kalan iş, kalan günlere zorlukla ağırlıklandırılarak dağıtılır.
  Günlük üst sınır aşılmaz. En verimli saat dilimi verisi yeterliyse (≥5 oturum) zor konular oraya konur.
- **Takip:** Her gün plan ile gerçekleşen (oturumlar ve test sonuçları) karşılaştırılır. Gün sonunda
  "yapılan / planlanan" görünür.
- **Değişen sistem:**
  - Geride kalınırsa kalan iş otomatik olarak yeniden dağıtılır ve bu bir bildirimle söylenir.
  - Üst sınır aşılacaksa program kendini zorlamaz; "hedefi küçült ya da tarihi uzat" önerisi üretir.
  - Üç gün üst üste %50'nin altında kalınırsa program bir öneri paketiyle hedefi düşürmeyi önerir.
- **Yapay zekâdan program:** Kullanıcı Claude Code'a "şunları şu kadar sürede bitireceğim" dediğinde Claude
  hedefleri bir `plan` öneri paketi olarak yazar. Programı uygulama hesaplar. Claude hedef gerçekçi değilse
  bunu sayıyla söyler (ör. "geçmiş tempon 2,4 dk/soru; bu plan günde 310 dk istiyor, ayarın 180").
- Bildirim: plandaki blok saatinde, blok başlamamışsa 15 dakika sonra tek hatırlatma.
