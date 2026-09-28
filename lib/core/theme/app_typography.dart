import 'package:flutter/material.dart';

/// Font đóng gói trong assets/fonts/BeVietnamPro (khai báo ở pubspec.yaml).
const appFontFamily = 'BeVietnamPro';

TextStyle _style(double size, double lineHeight, FontWeight weight) =>
    TextStyle(fontSize: size, height: lineHeight / size, fontWeight: weight);

/// Thang chữ theo DESIGN.md mục 2: Material 3, tăng cỡ body/label/title nhỏ
/// cho người lớn tuổi. letterSpacing để mặc định của Material 3.
final appTextTheme = TextTheme(
  displayLarge: _style(57, 64, FontWeight.w400),
  displayMedium: _style(45, 52, FontWeight.w400),
  displaySmall: _style(36, 44, FontWeight.w400),
  headlineLarge: _style(32, 40, FontWeight.w600),
  headlineMedium: _style(28, 36, FontWeight.w600),
  headlineSmall: _style(24, 32, FontWeight.w600),
  titleLarge: _style(22, 30, FontWeight.w600),
  titleMedium: _style(18, 26, FontWeight.w600),
  titleSmall: _style(16, 24, FontWeight.w500),
  bodyLarge: _style(18, 28, FontWeight.w400),
  bodyMedium: _style(16, 24, FontWeight.w400),
  bodySmall: _style(14, 20, FontWeight.w400),
  labelLarge: _style(16, 24, FontWeight.w600),
  labelMedium: _style(14, 20, FontWeight.w500),
  labelSmall: _style(12, 16, FontWeight.w500),
);
