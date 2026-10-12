# Koçum

YKS öğrencileri için tamamen çevrimdışı çalışma(ilk sürmler için), süre ve hata analizi takipçisi.
Flutter, Clean Architecture, SQLite (Drift). Telefonda denemek için `NASIL_DENENIR.md`.

## Özellikler

| Modül | Ne yapar |
|---|---|
| Kitaplar | Manuel ya da JSON şablonla (içe/dışa aktarma, paylaşma). Konular MEB kazanım ağacıyla eşleşir. |
| Oturum | Kitaptan (ünite, konu, tek sayfa) ya da kitapsız (ders, konu, video/konu anlatımı/soru çözümü). Durdurulamaz sayaç, iptal tuşu, bildirimde canlı kronometre, "Eksiklerini doldur" rozeti. |
| Optik form | Testin numaralarına dokunarak yanlış ve boş işaretleme. Doğru, yanlış, boş ve net kendiliğinden hesaplanır; sorular ders, konu ve süresiyle deftere düşer. |
| Plan | Tarih aralıklı görev havuzu; günlük program dayatmaz. Görevden doğrudan oturum başlar. |
| Defter | Yanlış / Boş / Doğru kartları. Fotoğraf ve çözüm isteğe bağlı; uygulama içi kırpma, WebP. Yıldız ile Güzel Sorular. Arama, filtreler, ağaç görünümü. |
| Eksikler | Fotoğrafı, çözümü, nedeni ya da konusu eksik kartlar. Neden ve fotoğraf satırdan tek dokunuşla eklenir. |
| Tekrar | "Yanlışlarımı göster": SM-2 (Anki). Fotoğrafsız kartlarda kitap, test ve soru numarası gösterilir. |
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
- Bir oturum bloğu birden fazla testi kapsıyorsa optik form numaraları blok boyunca sürer (1, 2, … 64). Kitap şablonları test yapısını içerdiğinde her test ayrı seçilebilecek.
- Konu listesi şimdilik yalnızca TYT Matematik ve TYT Türkçe için var; diğer derslerde örüntüler nedenlere göre çıkarılır.
