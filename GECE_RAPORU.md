# Gece raporu (14 Kasım 2026)

Her adım bitince güncellenir. `main`'e dokunulmadı, birleştirme yok.

## Biten adımlar

| Adım | Dal | Derleme |
|---|---|---|
| 0. CI: `v8.*`, `v9.*` dalları da APK üretir | `v8.5` | yeşil |
| 1. Sistem kontrolü (koc-arac) | — | — |
| 2. `koc esitle` + uçtan uca test (koc-arac) | koc-arac `main` (yerel) | `uv run pytest`: 30 geçti |
| 3. Koçum v8.5.1: tek kullanımlık eşitleme | `v8.5` | yeşil |
| 4. Koçum v8.6.0: Anlık | `v8.6.0` | (bekleniyor) |

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
- Anlıklar tam yedeğe (`kocum.backup` içinde `anlik`) de girer.

## Sabah telefonda deneme listesi
(APK: GitHub > Actions > ilgili dalın son "APK derle" işi > `kocum-apk`)

v8.5.1:
1. Bilgisayarda `cd ~/koc-arac && uv run koc sunucu`.
2. Telefonda Ayarlar > Bilgisayarla eşle > bilgisayarı seç > terminaldeki kodu yaz.
3. Terminalde "eşitlendi, yedek alındı" görünmeli.
4. İkinci terminalde `uv run koc esitle --yedek veri/kocum_yedek.json`: kodu sorar, sonra "Eşitlendi".

v8.6.0: `NASIL_DENENIR.md` > "Anlık (v8.6)" bölümündeki 10 adım.

## Önce okunacak 3 dosya
1. `lib/features/anlik/domain/etiket_metni.dart`: `((etiket))` nasıl bulunur (kısa, saf Dart).
2. `lib/features/anlik/domain/etiket_kurallari.dart`: bağlar, öneri sırası, ağaç, silme planı.
3. `lib/features/sync/data/koc_esitleyici.dart`: eşitleme bir uçtan bir uca (istekId, kayıtlar).

## Bitmeyenler
- (güncellenecek)
