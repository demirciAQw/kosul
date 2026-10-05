extension EnumByNameOr<T extends Enum> on List<T> {
  /// Veritabanında/JSON'da metin olarak saklanan enum'u güvenle çözer.
  /// Enum sırası değişse bile veri bozulmaz; bilinmeyen değerde [fallback] döner.
  T byNameOr(String? name, T fallback) => byNameOrNull(name) ?? fallback;

  T? byNameOrNull(String? name) => name == null ? null : asNameMap()[name];
}
