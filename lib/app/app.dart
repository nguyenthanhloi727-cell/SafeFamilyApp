import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/constants/app_info.dart';
import '../core/security/biometric_authenticator.dart';
import '../core/security/parent_guard.dart';
import '../core/security/secure_store.dart';
import '../core/settings/voice_language_settings.dart';
import '../core/theme/app_theme.dart';
import '../features/app_lock/data/app_lock_platform.dart';
import '../features/app_lock/presentation/app_lock_controller.dart';
import '../features/parental/presentation/first_run_setup_page.dart';
import 'app_shell.dart';

class SafeFamilyApp extends StatefulWidget {
  const SafeFamilyApp({super.key, this.guard, this.appLock});

  /// Mặc định: PIN/khóa lưu bằng flutter_secure_storage, sinh trắc qua
  /// local_auth. Test truyền bản giả.
  final ParentGuard? guard;

  /// Mặc định: app_blocker thật. Test truyền bản giả.
  final AppLockController? appLock;

  @override
  State<SafeFamilyApp> createState() => _SafeFamilyAppState();
}

class _SafeFamilyAppState extends State<SafeFamilyApp> {
  final _voiceLanguage = VoiceLanguageSettings()..load();
  late final ParentGuard _guard;
  late final AppLockController _appLock;

  @override
  void initState() {
    super.initState();
    _guard =
        widget.guard ??
        (ParentGuard(
            store: const FlutterSecureStore(),
            biometrics: LocalAuthBiometricAuthenticator(),
          )
          ..load()
          ..attachLifecycle());
    _appLock =
        widget.appLock ??
        (AppLockController(
          platform: AppBlockerPlatform(),
          onDisabled: _guard.recordWarning,
        )..start());
  }

  @override
  void dispose() {
    _voiceLanguage.dispose();
    if (widget.guard == null) _guard.dispose();
    if (widget.appLock == null) _appLock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ParentGuardScope(
      guard: _guard,
      child: AppLockScope(
        controller: _appLock,
        child: VoiceLanguageScope(
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
            home: _SecurityGate(guard: _guard),
          ),
        ),
      ),
    );
  }
}

/// Chưa đặt PIN → màn thiết lập lần đầu; đặt rồi → app chính.
class _SecurityGate extends StatelessWidget {
  const _SecurityGate({required this.guard});

  final ParentGuard guard;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: guard,
      builder: (context, _) {
        if (!guard.isLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!guard.isConfigured) return FirstRunSetupPage(guard: guard);
        return const AppShell();
      },
    );
  }
}
