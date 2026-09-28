import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/constants/app_info.dart';
import '../core/settings/voice_language_settings.dart';
import '../core/theme/app_theme.dart';
import 'app_shell.dart';

class SafeFamilyApp extends StatefulWidget {
  const SafeFamilyApp({super.key});

  @override
  State<SafeFamilyApp> createState() => _SafeFamilyAppState();
}

class _SafeFamilyAppState extends State<SafeFamilyApp> {
  final _voiceLanguage = VoiceLanguageSettings()..load();

  @override
  void dispose() {
    _voiceLanguage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VoiceLanguageScope(
      settings: _voiceLanguage,
      child: MaterialApp(
        title: AppInfo.displayName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light, // dark mode mới là bản nháp
        // Chữ có sẵn của Material (chọn giờ, OK/Hủy…) bằng tiếng Việt.
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const AppShell(),
      ),
    );
  }
}
