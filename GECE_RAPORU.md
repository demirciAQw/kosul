# Gece raporu (14 Kasım 2026)

Her adım bitince güncellenir. `main`'e dokunulmadı, birleştirme yok.

## Biten adımlar

| Adım | Dal | Derleme |
|---|---|---|
| 0. CI: `v8.*`, `v9.*` dalları da APK üretir | `v8.5` | yeşil |
| 1. Sistem kontrolü (koc-arac) | — | — |
| 2. `koc esitle` + uçtan uca test (koc-arac) | koc-arac `main` (yerel) | `uv run pytest`: 30 geçti |
| 3. Koçum v8.5.1: tek kullanımlık eşitleme | `v8.5` | yeşil |
| 4. Koçum v8.6.0: Anlık | `v8.6.0` | yeşil |
| 5. Koçum v8.6.1: etiket etiketi ve arama | `v8.6.1` | yeşil |
| 6. Koçum v8.7: noktasal grafik | `v8.7` | (bekleniyor) |
| 7. koc-arac adım 3: `koc oku`, `koc ozet`, `koc pano` | koc-arac `main` (yerel) | `uv run pytest`: 39 geçti |

### Sistem kontrolü (hiçbir şey kurulmadı)
- CachyOS, çekirdek 7.2.9; Python 3.14.10; uv 0.13.8; Flutter 3.50.0.
- Var: obsidian, kdeconnect (`kdeconnect-cli`), clang, cmake, ninja, pkg-config, gtk3 3.24.52,
  lld, libsecret. Yani Linux masaüstü derlemesi (v8.8) için gereken paketler kurulu görünüyor.
- Yok: `syncthing` (artık gerekmiyor; eşitleme `koc sunucu` ile).
- `nvidia-smi`: "Driver/library version mismatch". Sürücü güncellenmiş, bilgisayar yeniden
  başlatılmamış olabilir. GPU şu an gerekmiyor (v2 işi); yeniden başlatınca düzelir mi bak.
- `~/Koc` (Obsidian vault) yok. Sunucu yedeği yine `koc-arac/veri/`'ye yazar; vault'a yazmak
  için klasörü oluştur.
- koc-arac deposunun uzak sunucusu (`git remote`) yok: commit'ler sadece bu bilgisayarda.

## Kararlar
- **v8.8 yapılmadı.** Talimatında hem "v8.8'e geçme" hem "v9.0'a kadar gelsin" yazıyordu. Önce
  devam etmeyi seçtim ama v8.8 düzenlemelerim otomatik izin denetimince engellendi; güvenli yorumu
  ("v8.8'e geçme") seçip durdum. Yarım kalan v8.8 işi silinmedi, **stash'te**:
  `git stash list` → "v8.8 taslağı …" (masaüstünde bildirim/kamera/ML Kit kapatma, CI'da Linux işi,
  `lib/core/platform/cihaz.dart`). Devam istersen: `git switch -c v8.8 v8.7 && git stash pop stash@{1} && git stash pop`.
  Yerelde `flutter create --platforms linux` de engellendi; Linux derlemesi hiç denenmedi.
- **"Tek kullanımlık eşitleme"** = her `POST /esitle` isteği bir `istekId` taşır. Cevap yolda
  kaybolursa telefon aynı isteği bir kez yeniden yollar; sunucu kayıtları iki kez uygulamaz.
- **`koc esitle`** = bilgisayardan telefon gibi bir kez eşitleyen komut (elle deneme ve test için;
  ileride masaüstü uygulaması da aynı istekleri yapar).
- **CI kırmızıydı** (v8.5'in ilk derlemesi): `camera_android_camerax` lint'i JDK 17'de
  `List.removeLast` bulamıyordu. CI'da JDK 21'e geçildi; yeşil.
- CI'da testler `continue-on-error: true` (CLAUDE.md "testler geçmezse APK yok" diyor). Dokunmadım;
  istersen o satırı sil.
- `flutter analyze`: hata yok. ~90 bilgi notu var, çoğu Flutter 3.50'nin `material.dart` uyarısı
  (yeni `material_ui` paketi istiyor; paket kurmak yasak olduğu için bıraktım). Eskiden de vardı.
- `docs/TABLET_PDF.md` çalışma ağacında silinmiş ve `analysis_options.yaml` değişmiş halde
  duruyordu: senin değişikliğin olabilir diye hiçbir commit'e katmadım.
- Anlık: etiket adı benzersizliği veritabanında değil kodda (silinmiş etiketin adı yeniden
  kullanılabilsin diye).
- Anlık: kayıtta metinde adı bilinmeyen `((x))` varsa yeni etiket penceresi açılır; vazgeçilirse
  `x` düz yazı olur.
- Etiket geri alınınca metin bağları şerit bağı olur (metin silmede düz yazıya dönmüştü).
- Obsidian içe aktarmada bilinmeyen `((x))` için etiket kendiliğinden (tür: diğer) oluşur;
  pencere açmak yüzlerce dosyada olmaz.
- Eşitlemede aynı adlı iki etiket birleşir: daha eski olan kalır (iki tarafta aynı sonuç).
- Arama parçaları (`searchTokens`, `editDistance`, `tokenSimilarity`, `relevanceScore`) `core/text/fuzzy_search.dart`'a
  taşındı; `smart_search.dart` onları yeniden dışa veriyor, eski testler değişmeden geçiyor.
- Birleştirmede döngü kontrolü ayrı bir saf fonksiyon (`birlestirmeDonguOlurMu`); çift bağlar temizlenir.
- Kuvvet düzeninde itme sadece 60 birim yakındaki düğümler arasında (ızgara): 1550 düğüm testte birkaç saniye.
  Rastgelelik yok; üst üste düğümler sıra numarasına göre sabit yöne ayrılır.
- Takvim en fazla son ~1 yılı (370 gün) gösterir; daha eskisi sarmalı okunmaz yapardı.
- Ana etiketler: birden çok üstü olan alt etiket, adı alfabede önce gelen üstüne katlanır.
- Ekran duman testi (`test/anlik_ekran_test.dart`) gerçek bir hata yakaladı: isolate'e giden kapanış
  ekran durumunu taşıyordu, grafik telefonda açılmazdı. Düzeltildi.
- Anlıklar tam yedeğe (`kocum.backup` içinde `anlik`) de girer.

## Sabah telefonda deneme listesi
(APK: GitHub > Actions > ilgili dalın son "APK derle" işi > `kocum-apk`)

v8.5.1:
1. Bilgisayarda `cd ~/koc-arac && uv run koc sunucu`.
2. Telefonda Ayarlar > Bilgisayarla eşle > bilgisayarı seç > terminaldeki kodu yaz.
3. Terminalde "eşitlendi, yedek alındı" görünmeli.
4. İkinci terminalde `uv run koc esitle --yedek veri/kocum_yedek.json`: kodu sorar, sonra "Eşitlendi".

v8.6.0: `NASIL_DENENIR.md` > "Anlık (v8.6)" bölümündeki 10 adım.

v8.6.1: aynı belgede "Etiket etiketi ve arama (v8.6.1)" (8 adım).

v8.7: aynı belgede "Noktasal grafik (v8.7)" (7 adım).

koc-arac adım 3 (bilgisayarda):
1. `mkdir -p ~/Koc/{Günlük,Ödevler,Anlar}` (vault yoksa).
2. Telefonla bir kez eşitle (yedek `veri/kocum_yedek.json`'a gelsin).
3. `cd ~/koc-arac && uv run koc hepsi` → `~/Koc/Raporlar/ozet.md` ve `~/Koc/Panolar/` oluşur.
4. Bir günlük yaz, `uv run koc oku`: "Okundu: gunluk" der (sadece değişen grup).

## Önce okunacak 3 dosya
1. `lib/features/anlik/domain/etiket_metni.dart`: `((etiket))` nasıl bulunur (kısa, saf Dart).
2. `lib/features/anlik/domain/graf.dart`: sarmal yerleşim ve 5 görünüm (testi: `test/graf_test.dart`).
3. `lib/features/sync/data/koc_esitleyici.dart`: eşitleme bir uçtan bir uca (istekId, kayıtlar).
(koc-arac için: `koc/metrikler.py`.)

## Bitmeyenler
- v8.8 (eşitlemeye ayar/düzen/plan, Linux masaüstü), v8.9 (öneri kutusu), v9.0 (dinamik program):
  yukarıdaki karar yüzünden başlanmadı (v8.8 taslağı stash'te).
- koc-arac adım 4–5 (`koc bagla`, `koc kontrol`, timer'lar) ve ortak test örnekleri
  (`tests/anlik_ornekleri.yaml`, Dart ve Python aynı girdiler): sıra gelmedi.
- koc-arac'ın uzak deposu yok, commit'ler sadece bu bilgisayarda (3 commit).
- Telefonda denenemeyenler: Android "Anlık yaz" kısayolu, Obsidian dosya seçici, grafikte iki parmak
  yakınlaştırma. Testleri saf fonksiyon ve ekran duman testi olarak var; sabah listesinde.
