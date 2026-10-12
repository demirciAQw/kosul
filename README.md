# Koçum

YKS öğrencileri için tamamen çevrimdışı çalışma(ilk sürmler için), süre ve hata analizi takipçisi.
Flutter, Clean Architecture, SQLite (Drift). Telefonda denemek için `NASIL_DENENIR.md`.

## Özellikler

| Modül | Ne yapar |
|---|---|
| Kitaplar | Manuel ya da JSON şablonla (içe/dışa aktarma, paylaşma). Konular MEB kazanım ağacıyla eşleşir. |
| Oturum | Çoklu seçimli ağaç (ünite, konu, tek sayfa), tek BAŞLA, durdurulamaz sayaç, bildirimde canlı kronometre, "Eksiklerini doldur" rozeti. |
| Plan | Tarih aralıklı görev havuzu; günlük program dayatmaz. Görevden doğrudan oturum başlar. |
| Defter | Yanlış / Boş / Doğru kartları. Çek, kırp, sıkıştır (WebP). Doğru çözüm zorunlu. Yıldız ile Güzel Sorular. Arama, açılır menü filtreleri, Ders / Kitap / Konu ağacı. |
| Tekrar | "Yanlışlarımı göster": SM-2 (Anki) algoritması, günü gelen kartlar çözümüyle. |
| Analiz | En çok yanlış yapılan konu / neden / ders ve tahmini kayıp süre; son 7 gün çalışma süresi. |

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
   ├─ question_bank/    defter, filtre, SM-2, tekrar ekranı
   ├─ dashboard/        analiz
   └─ home/
```

Her özellik `domain/` (saf Dart), `data/` (Drift, JSON) ve `presentation/` (ekranlar) olarak ayrılır.
Bağımlılık yönü içe doğrudur: domain, Flutter'ı ya da veritabanını bilmez.

## Önemli kararlar

- **Sayaç tik saymaz:** süre her zaman `startedAt` damgasından hesaplanır. Uygulama kapansa da telefon yeniden başlasa da kaybolmaz.
- **Kurallar veritabanında da korunur:** doğru çözüm zorunluluğu (`CHECK`), aynı anda tek oturum (kısmi benzersiz indeks), zorluk 1-10.
- **Fotoğraf hattı:** çek/seç → kırp (tam çözünürlüklü orijinalde) → WebP. Yeniden kırpma her zaman orijinalden yapılır; kalite kaybı birikmez.
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
