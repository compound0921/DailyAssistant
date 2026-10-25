import 'package:flutter/material.dart';

/// 校园助手的视觉令牌。canon「温和卡片式应用」：
/// 暖中性底、白卡片、一个蓝色动作色，橙/红只用于紧迫度。
abstract final class AppColors {
  static const lightSurface = Color(0xFFF7F5F0);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightInk = Color(0xFF1B1B18);
  static const lightMuted = Color(0xFF6B6B63);
  static const lightOutline = Color(0xFFE6E0D6);
  static const lightPrimary = Color(0xFF2F6FED);
  static const lightPrimaryText = Color(0xFF1D4ED8);
  static const lightPrimaryContainer = Color(0xFFE7EEFF);
  static const lightUrgent = Color(0xFFD97706);
  static const lightDanger = Color(0xFFDC2626);

  static const darkSurface = Color(0xFF141512);
  static const darkCard = Color(0xFF1E1F1C);
  static const darkInk = Color(0xFFF2EFE8);
  static const darkMuted = Color(0xFFA6A69C);
  static const darkOutline = Color(0xFF343630);
  static const darkPrimary = Color(0xFF8FB3FF);
  static const darkPrimaryText = Color(0xFFB6CCFF);
  static const darkPrimaryContainer = Color(0xFF1B2A44);
  static const darkUrgent = Color(0xFFFBBF24);
  static const darkDanger = Color(0xFFF87171);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

TextStyle tabularFigures(TextStyle? style) {
  return (style ?? const TextStyle()).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ThemeData(useMaterial3: true, brightness: brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.lightPrimary,
        brightness: brightness,
      ).copyWith(
        primary: dark ? AppColors.darkPrimary : AppColors.lightPrimary,
        onPrimary: dark ? const Color(0xFF06122C) : Colors.white,
        primaryContainer: dark
            ? AppColors.darkPrimaryContainer
            : AppColors.lightPrimaryContainer,
        onPrimaryContainer: dark
            ? const Color(0xFFDCE7FF)
            : const Color(0xFF102A5C),
        secondary: dark ? AppColors.darkPrimary : AppColors.lightPrimary,
        onSecondary: dark ? const Color(0xFF06122C) : Colors.white,
        secondaryContainer: dark
            ? AppColors.darkPrimaryContainer
            : AppColors.lightPrimaryContainer,
        onSecondaryContainer: dark
            ? const Color(0xFFDCE7FF)
            : const Color(0xFF102A5C),
        surface: dark ? AppColors.darkSurface : AppColors.lightSurface,
        onSurface: dark ? AppColors.darkInk : AppColors.lightInk,
        onSurfaceVariant: dark ? AppColors.darkMuted : AppColors.lightMuted,
        outline: dark ? AppColors.darkOutline : const Color(0xFFB9B2A6),
        outlineVariant: dark ? AppColors.darkOutline : AppColors.lightOutline,
        error: dark ? AppColors.darkDanger : AppColors.lightDanger,
        errorContainer: dark
            ? const Color(0xFF3B1A18)
            : const Color(0xFFFEE4E2),
        onErrorContainer: dark
            ? const Color(0xFFFFC9C4)
            : const Color(0xFF7A1A12),
      );

  final text = base.textTheme.copyWith(
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontSize: 30,
      height: 1.1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontSize: 24,
      height: 1.15,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      fontSize: 14,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.45),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: base.textTheme.labelSmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );

  final cardColor = dark ? AppColors.darkCard : AppColors.lightCard;

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelSmall?.copyWith(
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cardColor,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.primary, size: 23),
      unselectedIconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: 23,
      ),
      selectedLabelTextStyle: text.labelMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      labelType: NavigationRailLabelType.all,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? AppColors.darkSurface : Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: text.labelLarge,
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        textStyle: text.labelLarge,
        foregroundColor: dark
            ? AppColors.darkPrimaryText
            : AppColors.lightPrimaryText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? AppColors.darkCard : AppColors.lightInk,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: dark ? AppColors.darkInk : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
    ),
  );
}
