# Koçum

YKS öğrencileri için tamamen çevrimdışı çalışma(ilk sürmler için), süre ve hata analizi takipçisi.
Flutter, Clean Architecture, SQLite (Drift). Telefonda denemek için `NASIL_DENENIR.md`.

## Tasarım (v6.0)

Google renkleri ve sade Material 3 bileşenleri: açık gri zemin üzerinde beyaz kartlar, ince çizgiler, hap biçimli düğmeler. Tek vurgu rengi mavi; yeşil, kırmızı ve sarı yalnızca anlam taşır (doğru, yanlış, boş). Koyu temada pastel tonlar. Tüm renkler `lib/app/palette.dart`, bileşen görünümü `lib/app/theme.dart`. Logo `tool/make_icon.py` ile üretilir.

## Özellikler

| Modül | Ne yapar |
|---|---|
| Kitaplar (sekme) | Her kitabın ne kadarı bitti, ne kadarı duruyor: ilerleme halkası, kitap haritası (her test bir kare, rengi sonucuna göre), ünite ünite test listesi. Testi elle çözüldü/çözülmedi yap; teste dokununca sonucu, yanlışların optiği ve fotoğrafları. Hazır kitaplar tek dokunuşla ya da JSON şablonla. |
| Oturum | Kitaptan (ünite, konu, tek sayfa) ya da kitapsız (ders, konu, video/konu anlatımı/soru çözümü). Durdurulamaz sayaç, iptal tuşu, bildirimde canlı kronometre, "Eksiklerini doldur" rozeti. |
| Optik form | Yanlış ve boşlara dokun; D/Y/B ve net kendiliğinden. Çok testli bir bölümde form test test bölünür: "6. test, 5. soru" (105. soru değil). Çözmediğin testi kapat. Sorular teste bağlanır, test kitap haritasında çözüldü olur. |
| Plan (Bugün'den) | İstediğin kadar plan: haftalık, aylık, yıllık ya da özel. Görev ekle/sil, planı "tamamladım" diye işaretle, sil (geri alınabilir). Görevden doğrudan oturum başlar. |
| Defter | Kitaptan eklerken yalnızca kitap, test ve soru no sorulur; konu testten gelir. Uzun basarak çoklu seçim ve toplu silme. "Diğer" nedenine kendi açıklaman. Yanlış / Boş / Doğru kartları. Fotoğraf ve çözüm isteğe bağlı; uygulama içi kırpma, WebP. Yıldız ile Güzel Sorular. Arama, filtreler, ağaç görünümü. |
| Eksikler | Fotoğrafı, çözümü, nedeni ya da konusu eksik kartlar. Neden ve fotoğraf satırdan tek dokunuşla eklenir. |
| Tekrar | "Yanlışlarımı göster": SM-2 (Anki). Fotoğrafsız kartlarda kitap, test ve soru numarası gösterilir. |
| Geçmiş oturumlar | Unutulan sayacın süresini düzelt, sonuçları sonradan düzenle, oturumu sil. |
| Karneden içe aktarma | Okul karnesi PDF'ini seç: deneme adı, tarih, kitapçık, ders ders D/Y/B, puan ve sıralar okunur; yanlış ve boşlar kazanımı, kitapçık numarası, doğru cevap ve senin cevabınla deftere düşer. Birden çok karne aynı anda seçilebilir. Girilmemiş seçmeli bölüm (Seçmeli Felsefe) atlanır. |
| Araçlar (sekme) | Kitapları bitirme hedefi (kalan test, günde gereken hız); Claude'a görselsiz paket: yalnızca son paketten bu yana yeni veriler ya da tüm veri, numaralı ve tarihli (Paket #N); yanlış defteri PDF (sayfada 4 soru, cevap anahtarı); yanlışlarımdan test (ders, konu, zorluk, karma, hata nedeni, zayıf konuların hepsi); tüm veriyi dışa aktarma (JSON + fotoğraflar); tema. |
| Tablo (LibreOffice Calc) | Araçlar'dan tüm veri tek .xlsx dosyasında, sekiz sayfa: Sorular, Oturumlar, Kitap testleri, Kitaplar, Denemeler, Bulgular, Notlar, Planlar. Başlıklar kalın ve sabit, filtre açık; tarihler gerçek tarih, sayılar gerçek sayı. Defter'den seçili sorular da tabloya aktarılabilir. Paket gerektirmeyen yazıcı; LibreOffice ile doğrulandı. |
| Dışa aktarma | Defter'den seçili sorular, o anki arama/filtre ya da tüm defter tek ZIP olarak paylaşılır: soru ve çözüm fotoğrafları (etiketle, tarihle ya da sıra numarasıyla adlandırılmış, istenirse derslere göre klasörlü), Excel'de açılan etiket tablosu ve istenirse tüm veri (JSON). Notlar da Markdown metni ve sayfa fotoğraflarıyla dışa aktarılır. |
| Deneme | TYT / AYT (alan seçmeli) / YDT / branş. Ders bazlı net, net grafiği, son 5 ortalamasına göre fark, konu bazlı net kaybı (yanlış 1,25, boş 1 net). |
| Analiz | Derslere göre örüntüler ("Problemler sorularında en sık neden işlem hatası"), en çok yanlış yapılan konu / neden / ders, tahmini kayıp süre, son 7 gün çalışma süresi. |

## Mimari

```
lib/
├─ main.dart            kompozisyon kökü (veritabanı, medya, bildirim, MEB tohumlama)
├─ app/                 kabuk, alt gezinme, router, tema
├─ core/                database, media, notifications, json, text, utils
└─ features/
   ├─ curriculum/       MEB ağacı + Türkçe konu eşleştirici
   ├─ library/          kitaplar + JSON şablon sözleşmesi
   ├─ study_session/    seçim ağacı, sayaç, sonuç girişi
   ├─ planning/         tarih aralıklı görev havuzu
   ├─ question_bank/    defter, filtre, SM-2, tekrar, optik form, Eksikler
   ├─ mock_exam/        denemeler, net analizi, konu bazlı net kaybı
   ├─ dashboard/        analiz, ders bazlı örüntüler
   └─ home/
```

Her özellik `domain/` (saf Dart), `data/` (Drift, JSON) ve `presentation/` (ekranlar) olarak ayrılır.
Bağımlılık yönü içe doğrudur: domain, Flutter'ı ya da veritabanını bilmez.

## Önemli kararlar

- **Sayaç tik saymaz:** süre her zaman `startedAt` damgasından hesaplanır. Uygulama kapansa da telefon yeniden başlasa da kaybolmaz.
- **Kurallar veritabanında da korunur:** aynı anda tek oturum (kısmi benzersiz indeks), zorluk 1-10, deneme sayıları soru sayısını geçemez (`CHECK`).
- **Önce kaydet, sonra tamamla (v2):** yalnızca ders zorunlu. Fotoğraf, çözüm, neden ve konu sonradan Eksikler'den eklenir.
- **Fotoğraf hattı:** çek/seç (en uzun kenar 4096) → uygulama içi kırpma ve döndürme → WebP. Yeniden kırpma her zaman orijinalden yapılır; kalite kaybı birikmez.
- **Optik form defterle eşitlenir:** yeni işaret kart açar, kaldırılan işaret yalnızca üzerinde emek olmayan kartı siler.
- **Kayıp süre tahmindir:** yanlış sayısı × o testteki soru başına ortalama süre.

## Kitap şablonu JSON sözleşmesi (v1)

Örnek: `assets/templates/345_TYT_Mat.json`

| Alan | Zorunlu | Not |
|---|---|---|
| `schemaVersion` | evet | uygulamadan yeni sürüm reddedilir |
| `book.title`, `examType` (TYT/AYT/YDT), `subject`, `pageCount`, `avgQuestionsPerPage` | evet | |
| `units[].title` | evet | `children` ile en fazla 3 seviye |
| `pageStart` / `pageEnd` | birlikte | 1..pageCount, başlangıç ≤ bitiş |
| `meb` | hayır | açık MEB kimliği; otomatik eşleştirmeyi geçersiz kılar |
| `questions` | hayır | testteki kesin soru sayısı (1–500); sayfasız test başlıkları için idealdir |

Hatalar tam yolla bildirilir: `$.units[2].children[0].pageEnd`. Sınırlar: 2 MB, 5000 başlık.

## Geliştirici komutları

```bash
tool/setup.sh                                           # Android iskeleti + paketler + kod üretimi
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run --release
```

## Bilinen sınırlar

- `assets/meb/kazanim_agaci.json` ve örnek kitap **örnek veridir**; yayından önce gerçek MEB/ÖSYM konu listesiyle doldurulmalı.
- Düşük güvenli MEB eşleşmeleri için onay ekranı yok (şimdilik otomatik eşleşme ve "onay bekliyor" sayacı var).
- Yedekleme / geri yükleme (JSON + medya zip) yok.(claude codean yapıyo bu işi )
- Şablonda test yapısı yoksa (yalnızca sayfa aralığı) optik form numaraları seçilen blok boyunca sürer. Testleri `questions` alanıyla tanımlanmış kitaplarda her test ayrı seçilir ve numaralar teste göredir.
- Konu listesi şimdilik yalnızca TYT Matematik ve TYT Türkçe için var; diğer derslerde örüntüler nedenlere göre çıkarılır.
- Karne içe aktarma, "Bölüm Analizi" + soru soru kazanım tablosu olan karne biçimini tanır (ör. Maarif/Mikroorjinal karneleri). Birleştirilmiş karne tek bir denemeye karşılık gelmediği için içe aktarılmaz. PDF okuma `syncfusion_flutter_pdf` ile yapılır (Syncfusion topluluk lisansı: bireysel kullanım ücretsiz).
- Deneme optiğinde aynı testi paylaşan dersler kitapçık numarasıyla gösterilir (TYT Fen: Fizik 1–7, Kimya 8–14, Biyoloji 15–20). v0.5 öncesi bu derslere elle işaretlenmiş soruların numaraları 1'den başlıyordu; bunlar defterde kalır ama optikte görünmez.
- Kitap yapısı (ünite/test) uygulama içinde düzenlenemez; adı ve yayınevi düzenlenebilir. Yapı değişikliği için JSON şablonu güncellenip yeniden içe aktarılır.
- Uygulama simgesi `tool/make_icon.py` ile üretilir; derlemede `tool/patch_android.dart` simgeleri Android klasörüne kopyalar.
