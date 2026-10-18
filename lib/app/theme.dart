import 'package:flutter/material.dart';

import 'palette.dart';

/// Google tarzı, sade ve sakin bir arayüz: beyaz kartlar, ince gri çizgiler,
/// hap biçimli düğmeler, tek bir mavi vurgu. Göz yormaz; renk yalnızca anlam
/// taşıdığında kullanılır.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness b) {
    final dark = b == Brightness.dark;
    final base = ColorScheme.fromSeed(seedColor: KocumColors.blue, brightness: b);
    return dark
        ? base.copyWith(
            primary: KocumColors.blueDark,
            onPrimary: const Color(0xFF062E6F),
            primaryContainer: const Color(0xFF0842A0),
            onPrimaryContainer: const Color(0xFFD3E3FD),
            secondary: KocumColors.greenDark,
            onSecondary: const Color(0xFF0D3B1E),
            secondaryContainer: const Color(0xFF0F5223),
            onSecondaryContainer: const Color(0xFFC4EED0),
            tertiary: KocumColors.yellowDark,
            onTertiary: const Color(0xFF3F2E00),
            tertiaryContainer: const Color(0xFF5B4300),
            onTertiaryContainer: const Color(0xFFFFEFC2),
            error: KocumColors.redDark,
            surface: const Color(0xFF1F1F1F),
            onSurface: KocumColors.grey200,
            onSurfaceVariant: KocumColors.grey500,
            surfaceContainerLowest: const Color(0xFF141414),
            surfaceContainerLow: const Color(0xFF242526),
            surfaceContainer: const Color(0xFF292A2D),
            surfaceContainerHigh: const Color(0xFF303134),
            surfaceContainerHighest: KocumColors.grey800,
            outline: KocumColors.grey700,
            outlineVariant: KocumColors.grey800,
          )
        : base.copyWith(
            primary: KocumColors.blue,
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFD3E3FD),
            onPrimaryContainer: const Color(0xFF041E49),
            secondary: KocumColors.green,
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFCEEAD6),
            onSecondaryContainer: const Color(0xFF0D3B1E),
            tertiary: const Color(0xFFB06000),
            onTertiary: Colors.white,
            tertiaryContainer: const Color(0xFFFEEFC3),
            onTertiaryContainer: const Color(0xFF3F2E00),
            error: KocumColors.red,
            surface: Colors.white,
            onSurface: KocumColors.grey900,
            onSurfaceVariant: KocumColors.grey700,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: KocumColors.grey50,
            surfaceContainer: KocumColors.grey100,
            surfaceContainerHigh: KocumColors.grey200,
            surfaceContainerHighest: KocumColors.grey200,
            outline: KocumColors.grey500,
            outlineVariant: KocumColors.grey300,
          );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = _scheme(brightness);
    final dark = brightness == Brightness.dark;
    const pill = StadiumBorder();
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return base.copyWith(
      // Zemin hafif gri, kartlar beyaz: Google uygulamalarındaki katman hissi.
      scaffoldBackgroundColor: dark ? scheme.surface : KocumColors.grey50,
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w500),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.1),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? scheme.surface : KocumColors.grey50,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w500, fontSize: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? scheme.surfaceContainerLow : Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? scheme.surfaceContainer : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: pill,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: pill,
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: pill)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 1,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outlineVariant),
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelLarge,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: dark ? scheme.surfaceContainer : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
        labelStyle: text.titleSmall,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: dark ? KocumColors.grey200 : KocumColors.grey800,
        contentTextStyle: text.bodyMedium?.copyWith(color: dark ? KocumColors.grey900 : Colors.white),
        actionTextColor: dark ? KocumColors.blue : KocumColors.blueDark,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? scheme.surfaceContainerHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
    );
  }
}
