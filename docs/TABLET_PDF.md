# Tablet + PDF modu: tarif

## Hedef

**Telefonda elle yapılan her şey PDF modunda kendiliğinden olsun.** Öğrenci
PDF'i açar, kalemle çözer, şıkkı işaretler. Uygulama:

- soruları PDF'ten bulur (numara, kök, şıklar, konum),
- her soruda geçen süreyi ölçer,
- cevap anahtarıyla otomatik kontrol eder,
- yanlış ve boşları **fotoğrafsız** deftere kaydeder (PDF'teki yeri + çözüm
  çizgileri),
- konu ve soru türünü otomatik etiketler,
- çözümü saydam bir katmanda saklar ve tekrar sırasında **"çözümü getir"** ile
  sorunun üstüne yeniden serer.

Öğrenciye kalan tek iş (isteğe bağlı): yanlışın nedenini tek dokunuşla seçmek.

Telefon akışı (fotoğraf, optik, karne) olduğu gibi kalır. İki kanal da aynı
deftere, aynı analize, aynı tekrar sistemine akar.

## Örnek senaryo

1. Öğrenci "Bilgi Sarmal Fizik" PDF'ini içe aktarır, kitaplıktaki kitapla
   eşler (sayfa → test eşlemesi kitap şablonundan gelir).
2. Test 5'i açar, kalemle çözer, şıkları daire içine alır.
3. "Testi bitir": uygulama cevap anahtarıyla karşılaştırır: 12 doğru, 2 yanlış,
   1 boş. Süreler: soru başı ortalama 74 sn; 7. soru 3 dk 10 sn.
4. 2 yanlış + 1 boş deftere eklenir: kaynak, test, soru no, konu (otomatik),
   doğru cevap, öğrencinin cevabı, süre. Fotoğraf yok; görsel, PDF'ten o an
   kesilerek gösterilir.
5. Tekrar zamanı: soru temiz hâliyle gelir. "Çözümümü göster" ilk denemedeki
   çizgileri saydam olarak serer.

## Teknik seçimler

- PDF görüntüleme ve metin katmanı: **pdfrx** (MIT, PDFium). Metin parçaları
  ve karakter kutuları API'sini kaynak koddan doğrula; tahmin etme.
- Kalem çizgisi: **perfect_freehand** (MIT): baskıya göre doğal çizgi.
- El yazısı tanıma (sonraki aşama): **ML Kit Digital Ink Recognition**
  (`google_mlkit_digital_ink_recognition`, dil `tr`; model ilk kullanımda iner).
- GPL kod (ör. Saber) alınmaz; yalnızca fikir.
- Model dosyası gömülmez; APK boyutu korunur.

## Veri modeli (veritabanı v12, öneri)

- `pdf_documents`: id, title, filePath, pageCount, sha256, bookId (nullable),
  pageOffset (PDF sayfası ↔ kitap sayfası), createdAt.
- `ink_strokes`: id, documentId, page, layer (`solution` | `mark` | `note`),
  attempt (1, 2, …), tool (`pen` | `highlighter`), color, width, points
  (sıkıştırılmış ikili: x, y, baskı, zaman farkı), createdAt.
- `pdf_questions`: id, documentId, page, number, box (sayfa koordinatı),
  contentNodeId (test), answerKey (nullable), detectedBy (`text` | `ocr`).
- `question_cards`'a yeni boş geçilebilir sütunlar: `pdfDocumentId`, `pdfPage`,
  `pdfBox`. Bu sütunlar doluysa kartın fotoğrafı gerekmez.

Göç kuralı: eski sürümlerden gelen her yol test edilir (`CLAUDE.md`).

## Aşamalar

Her aşama ayrı sürüm, ayrı testler; telefon akışı her aşamada çalışır kalır.

### A. Tablet yerleşimi
- Genişlik ≥ 600 dp: alt menü yerine `NavigationRail`.
- Defter: solda liste, sağda seçili soru (iki bölme). Analiz, Deneme, Kitaplar
  geniş ekrana uyarlanır.
- Kabul: telefon görünümü değişmez; tablet emülatöründe (Pixel Tablet) taşma yok.

### B. PDF kitaplığı ve okuyucu
- PDF içe aktar (dosya seçici), uygulama klasörüne kopyala, kitapla eşle.
- Sayfa küçük resimleri, akıcı kaydırma ve yakınlaştırma, son kalınan sayfa.
- Kabul: 300 sayfalık PDF'te sayfa açılışı < 300 ms (orta seviye tablet).

### C. Saydam kalem katmanı ("filigran")
- Kalem çizer, parmak kaydırır (`PointerDeviceKind.stylus`); ayarda "parmakla da
  çiz". Avuç içi temasları yok sayılır.
- Araçlar: kalem, fosforlu kalem, silgi (çizgi silme), geri al / yinele, renk.
- Çizgiler vektör olarak, sayfa koordinatında saklanır; otomatik kaydedilir.
- Akıcılık: biten çizgiler sayfa başına resme dönüştürülüp önbelleklenir;
  yalnızca o an çizilen çizgi canlı çizilir.
- Kabul: 2000 çizgili sayfada kaydırma takılmaz; uygulama kapanınca çizgi
  kaybolmaz.

### D. Soruları PDF'ten bulma
- Metin katmanı olan PDF: metin parçaları → `OcrLine`/`OcrWord` →
  mevcut `readPage` (`features/ocr/domain/reader/page_reader.dart`). OCR yok.
- Taranmış PDF: sayfa resme çizilir → mevcut ML Kit motoru → aynı yol.
- Sonuç `pdf_questions`'a yazılır (numara, kutu, şıklar).
- Kabul: örnek PDF'lerde soru kutuları ve şıklar test fikstürleriyle doğrulanır.

### E. Şık işaretleme ve otomatik kontrol
- İşaret: bir şık kutusunu çevreleyen (daire) ya da üstünden geçen (çarpı,
  tik) çizgi → seçilen şık. "İşaret modu"nda şıkka dokunmak da olur.
- Cevap anahtarı, sırasıyla: kitap şablonundaki anahtar; PDF'teki anahtar
  sayfası (`12. C`, `12-C`, tablo düzenleri); bir kez elle giriş (A–E ızgarası).
- "Testi bitir" ile puanlama; sonuç mevcut test sonucu kaydına (`TestResult`)
  ve kitap haritasına yazılır.
- Kabul: işaret algılama için çizgi fikstürleriyle testler (daire, tik, çarpı,
  karalama).

### F. Yanlışı otomatik kaydetme (fotoğrafsız)
- Yanlış ve boş → `QuestionCard`: kaynak, kitap, test, soru no, ders, konu
  (`auto_tags`), soru kökü türü, doğru cevap, öğrenci cevabı, süre, PDF yeri.
- Görsel: kart açılınca PDF'ten o bölge çizilir (dosya saklanmaz). Dışa
  aktarma (PDF, ZIP) da aynı yoldan çizer.
- Neden: kayıttan sonra küçük bir panel, tek dokunuş, atlanabilir.
- Kabul: defter, arama, analiz ve Claude raporu bu kartları fotoğraflılar gibi
  gösterir.

### G. Çözümü getir
- Kart ve tekrar ekranında soru temiz gelir. "Çözümümü göster" ilk denemenin
  `solution` çizgilerini saydam serer (saydamlık ayarlanabilir).
- "Yeniden çöz" yeni bir deneme (`attempt + 1`) açar; eski çözüm korunur.
- Kabul: iki denemenin çizgileri ayrı saklanır ve ayrı gösterilir.

### H. Süre ve oturum
- Soru başı süre: o sorunun kutusundaki çizgi zamanları + ekranda görünme süresi.
- İlk çizgide otomatik çalışma oturumu başlar, 10 dk hareketsizlikte biter;
  mevcut oturum ve derin analiz bu veriyi kullanır.
- Kabul: süre hesaplama saf fonksiyon ve testli.

### Sonraki aşamalar
- El yazısında arama (Digital Ink, `tr`; sonuçlar sayfaya gider ve vurgular).
- Video çözüm bağlantısı: soru başına bağlantı + saniye ("Çözümü izle").
- Benzer soru bağlama, bir görseli birden çok soruya bağlama.

## Kapsam dışı

Şablonlar, çoklu katman yönetimi, bulut senkronu, el yazısını metne dönüştürüp
düzenleme. Bunlar test çözmeye katkı sağlamadıkça eklenmez.

## Telif

Yalnızca yasal PDF'ler: MEB/OGM kitapları ve kullanıcının kendi taramaları.
İnternetten içerik indirip çıkaran özellik eklenmez; video çözümler yalnızca
bağlantı + zaman damgası olarak tutulur.

## Doğrulama

- Her aşamada `flutter analyze` + `flutter test` temiz.
- Tablet emülatörü (Pixel Tablet) ile ekran görüntüsü; kalem hissi gerçek
  tablette kullanıcı tarafından denenir.
- Performans ölçümleri sürüm notuna yazılır.
