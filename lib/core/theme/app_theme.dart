import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Gom màu, chữ, bo góc, kích thước thành [ThemeData] Material 3.
abstract final class AppTheme {
  static ThemeData get light => _build(lightColorScheme, AppColors.light);

  /// Nháp — chưa bật (xem `themeMode` trong app.dart).
  static ThemeData get dark => _build(darkColorScheme, AppColors.dark);

  static ThemeData _build(ColorScheme scheme, AppColors appColors) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: appFontFamily,
      textTheme: appTextTheme,
    );
    final text = base.textTheme;

    const pill = StadiumBorder();
    const buttonSize = Size(AppSize.touchMin, AppSize.buttonHeight);
    final buttonText = WidgetStatePropertyAll(text.labelLarge);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      extensions: [appColors],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(buttonSize),
          shape: const WidgetStatePropertyAll(pill),
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(buttonSize),
          shape: const WidgetStatePropertyAll(pill),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSize.touchMin, AppSize.buttonHeightSmall),
          ),
          shape: const WidgetStatePropertyAll(pill),
          textStyle: buttonText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: text.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      // 4 tab chế độ Dịch ở 360 dp: chữ 14sp + đệm nhỏ để "Giọng nói" không bị cắt.
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: text.labelMedium,
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      // Thầy chấm widget BottomNavigationBar (không dùng NavigationBar).
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: scheme.surfaceContainerLowest,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        selectedLabelStyle: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: text.labelMedium,
        showUnselectedLabels: true,
        elevation: 3,
      ),
    );
  }
}
