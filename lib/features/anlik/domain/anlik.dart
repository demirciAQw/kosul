// Anlık verisinin modelleri (saf Dart): anlık, etiket ve bağ.
//
// Anlık: kısa bir not ("garsonu çağıramadım"). Etiket: ((his)) gibi bir ad.
// Bağ: anlık → etiket (etiketli), etiket → üst etiket (ust), anlık ↔ anlık (ilgili).
// Her kayıt eşitlenir: guncelleme (zaman), silindi (yumuşak silme) ve
// esitlenmedi (son eşitlemeden beri değişti) alanlarını taşır.

enum EtiketTur {
  kisi('Kişi'),
  duygu('Duygu'),
  konu('Konu'),
  yer('Yer'),
  diger('Diğer');

  const EtiketTur(this.ad);
  final String ad;

  static EtiketTur coz(Object? s) => values.firstWhere((t) => t.name == s, orElse: () => EtiketTur.diger);
}

enum BagTip {
  etiketli,
  ust,
  ilgili;

  static BagTip coz(Object? s) => values.firstWhere((t) => t.name == s, orElse: () => BagTip.etiketli);
}

/// Bağın nereden geldiği: metindeki ((…)), etiket şeridi, elle, yapay zekâ.
enum BagNeden {
  metin,
  serit,
  elle,
  ai;

  static BagNeden coz(Object? s) => values.firstWhere((t) => t.name == s, orElse: () => BagNeden.elle);
}

enum BagDurum {
  onerildi,
  onayli,
  reddedildi;

  static BagDurum coz(Object? s) => values.firstWhere((t) => t.name == s, orElse: () => BagDurum.onayli);
}

/// Kaydın uçları: anlık ya da etiket.
enum UcTur {
  anlik,
  etiket;

  static UcTur coz(Object? s) => values.firstWhere((t) => t.name == s, orElse: () => UcTur.anlik);
}

class Anlik {
  const Anlik({
    required this.id,
    required this.metin,
    required this.olusturma,
    required this.guncelleme,
    this.duygu,
    this.cihaz = '',
    this.silindi = false,
    this.esitlenmedi = true,
  });

  final String id;
  final String metin;
  final DateTime olusturma;
  final DateTime guncelleme;

  /// -3 … +3; boş bırakılabilir (bilinmiyor, sıfır değil).
  final int? duygu;
  final String cihaz;
  final bool silindi;
  final bool esitlenmedi;
}

class Etiket {
  const Etiket({
    required this.id,
    required this.ad,
    required this.normAd,
    required this.olusturma,
    required this.guncelleme,
    this.tur = EtiketTur.diger,
    this.renk,
    this.olusturan = 'ben',
    this.silindi = false,
    this.esitlenmedi = true,
  });

  final String id;
  final String ad;

  /// normalizeTr(ad): aynı normalize ada sahip iki etiket olamaz.
  final String normAd;
  final EtiketTur tur;

  /// ARGB renk; boşsa türün rengi.
  final int? renk;

  /// "ben" ya da "ai".
  final String olusturan;
  final DateTime olusturma;
  final DateTime guncelleme;
  final bool silindi;
  final bool esitlenmedi;
}

class Bag {
  const Bag({
    required this.id,
    required this.tip,
    required this.kaynakTur,
    required this.kaynakId,
    required this.hedefTur,
    required this.hedefId,
    required this.olusturma,
    required this.guncelleme,
    this.neden = BagNeden.elle,
    this.durum = BagDurum.onayli,
    this.puan,
    this.silindi = false,
    this.esitlenmedi = true,
  });

  final String id;
  final BagTip tip;
  final UcTur kaynakTur;
  final String kaynakId;
  final UcTur hedefTur;
  final String hedefId;
  final BagNeden neden;
  final BagDurum durum;
  final double? puan;
  final DateTime olusturma;
  final DateTime guncelleme;
  final bool silindi;
  final bool esitlenmedi;

  /// Görünür bağ: silinmemiş ve reddedilmemiş.
  bool get etkin => !silindi && durum != BagDurum.reddedildi;
}
