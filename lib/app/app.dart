import 'package:flutter/material.dart';

import '../core/constants/app_info.dart';
import '../core/theme/app_theme.dart';
import 'app_shell.dart';

class SafeFamilyApp extends StatelessWidget {
  const SafeFamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.displayName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light, // dark mode mới là bản nháp
      home: const AppShell(),
    );
  }
}
