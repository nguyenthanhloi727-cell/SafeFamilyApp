import 'package:flutter/material.dart';

// Màu theo DESIGN.md mục 1. Đổi màu → sửa DESIGN.md trước, rồi sửa ở đây.

/// `color/*` light — app đang dùng.
const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF00796B),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFB8EDE0),
  onPrimaryContainer: Color(0xFF00201B),
  secondary: Color(0xFFB45309),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFFFE0C2),
  onSecondaryContainer: Color(0xFF3A1D00),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFF6FAF8), // color/background
  onSurface: Color(0xFF171D1B), // color/text/primary
  onSurfaceVariant: Color(0xFF3F4946), // color/text/secondary
  surfaceContainerLowest: Color(0xFFFFFFFF), // color/surface/main
  surfaceContainerHighest: Color(0xFFDBE5E1), // color/surface/variant
  outline: Color(0xFF6F7976),
  outlineVariant: Color(0xFFBFC9C5),
  scrim: Color(0xFF000000),
);

/// `color/*` dark — bản NHÁP để chừa chỗ, chưa kiểm tra tương phản, chưa bật.
const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF5DD9C1),
  onPrimary: Color(0xFF00382F),
  primaryContainer: Color(0xFF005046),
  onPrimaryContainer: Color(0xFFB8EDE0),
  secondary: Color(0xFFFFB77C),
  onSecondary: Color(0xFF4A2800),
  secondaryContainer: Color(0xFF6A3B00),
  onSecondaryContainer: Color(0xFFFFE0C2),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF0F1513),
  onSurface: Color(0xFFDEE4E1),
  onSurfaceVariant: Color(0xFFBFC9C5),
  surfaceContainerLowest: Color(0xFF171D1B),
  surfaceContainerHighest: Color(0xFF303634),
  outline: Color(0xFF899390),
  outlineVariant: Color(0xFF3F4946),
  scrim: Color(0xFF000000),
);

/// Màu không có trong [ColorScheme]: success / warning / overlay camera.
///
/// Dùng: `Theme.of(context).extension<AppColors>()!`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.cameraTextBackground,
    required this.cameraText,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color cameraTextBackground;
  final Color cameraText;

  static const light = AppColors(
    success: Color(0xFF2E7D32),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFC8E6C9),
    warning: Color(0xFF8A5A00),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFE8B0),
    cameraTextBackground: Color(0x99000000), // đen 60%
    cameraText: Color(0xFFFFFFFF),
  );

  /// Nháp — đi cùng [darkColorScheme].
  static const dark = AppColors(
    success: Color(0xFF81C784),
    onSuccess: Color(0xFF0B3A0E),
    successContainer: Color(0xFF1B5E20),
    warning: Color(0xFFFFCA66),
    onWarning: Color(0xFF442B00),
    warningContainer: Color(0xFF624000),
    cameraTextBackground: Color(0x99000000),
    cameraText: Color(0xFFFFFFFF),
  );

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? cameraTextBackground,
    Color? cameraText,
  }) {
    return AppColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      cameraTextBackground: cameraTextBackground ?? this.cameraTextBackground,
      cameraText: cameraText ?? this.cameraText,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      cameraTextBackground: Color.lerp(
        cameraTextBackground,
        other.cameraTextBackground,
        t,
      )!,
      cameraText: Color.lerp(cameraText, other.cameraText, t)!,
    );
  }
}
