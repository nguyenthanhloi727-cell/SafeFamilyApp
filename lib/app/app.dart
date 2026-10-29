import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/constants/app_info.dart';
import '../core/permissions/permission_registry.dart';
import '../core/security/biometric_authenticator.dart';
import '../core/security/device_guard.dart';
import '../core/security/parent_guard.dart';
import '../core/security/secure_store.dart';
import '../core/security/ui/pin_prompt_page.dart';
import '../core/settings/setup_settings.dart';
import '../core/settings/theme_settings.dart';
import '../core/settings/voice_language_settings.dart';
import '../core/theme/app_theme.dart';
import '../features/app_lock/data/app_lock_platform.dart';
import '../features/app_lock/presentation/app_lock_controller.dart';
import '../features/new_app/data/new_app_platform.dart';
import '../features/new_app/presentation/new_apps_page.dart';
import '../features/parental/presentation/first_run_setup_page.dart';
import '../features/setup/setup_wizard_page.dart';
import '../features/time_limit/data/time_limit_platform.dart';
import '../features/time_limit/presentation/extra_time.dart';
import 'app_shell.dart';

class SafeFamilyApp extends StatefulWidget {
  const SafeFamilyApp({
    super.key,
    this.guard,
    this.appLock,
    this.permissions,
    this.setup,
  });

  /// Mặc định: PIN/khóa lưu bằng flutter_secure_storage, sinh trắc qua
  /// biometric_storage. Test truyền bản giả.
  final ParentGuard? guard;

  /// Mặc định: app_blocker thật. Test truyền bản giả.
  final AppLockController? appLock;

  /// Mặc định: hỏi Android thật. Test truyền bản giả.
  final PermissionRegistry? permissions;

  /// Mặc định: cờ `setup_done` trong SharedPreferences. Test truyền bản giả.
  final SetupSettings? setup;

  @override
  State<SafeFamilyApp> createState() => _SafeFamilyAppState();
}

class _SafeFamilyAppState extends State<SafeFamilyApp> {
  final _voiceLanguage = VoiceLanguageSettings()..load();
  final _themeSettings = ThemeSettings()..load();
  late final ParentGuard _guard;
  late final AppLockController _appLock;
  late final PermissionRegistry _permissions;
  late final SetupSettings _setup;
  final _navigatorKey = GlobalKey<NavigatorState>();
  AppLifecycleListener? _lifecycle;
  bool _challenging = false;

  @override
  void initState() {
    super.initState();
    _guard =
        widget.guard ??
        (ParentGuard(
            store: const FlutterSecureStore(),
            biometrics: BiometricStorageAuthenticator(
              store: const FlutterSecureStore(),
            ),
            device: const MethodChannelDeviceGuard(),
          )
          ..load()
          ..attachLifecycle());
    _appLock =
        widget.appLock ??
        (AppLockController(
          platform: AppBlockerPlatform(),
          onDisabled: _guard.recordWarning,
        )..start());
    _permissions = widget.permissions ?? (PermissionRegistry()..start());
    _setup = widget.setup ?? (SetupSettings()..load());
    // Dịch vụ "Bảo vệ cài đặt" đưa con về SafeFamily khi con mở màn nguy hiểm
    // → app hiện lên (mở mới hoặc quay lại) thì hỏi PIN.
    _lifecycle = AppLifecycleListener(onResume: _checkRequests);
    _guard.addListener(_onGuardChanged);
  }

  bool _checkedAtStart = false;

  void _onGuardChanged() {
    // Lần đầu khóa phụ huynh tải xong (mở app lúc dịch vụ vừa đẩy con về).
    if (_checkedAtStart || !_guard.isLoaded) return;
    _checkedAtStart = true;
    _checkRequests();
  }

  Future<void> _checkRequests() async {
    await _checkChallenge();
    await _checkExtraTime();
    await _checkNewAppReview();
  }

  /// Phụ huynh bấm thông báo "Con vừa cài app X" (hoặc con bấm "Nhờ bố mẹ
  /// duyệt"): mở màn duyệt. Việc cho phép từng app vẫn phải xác thực.
  Future<void> _checkNewAppReview() async {
    if (!_guard.isLoaded || !_guard.isConfigured) return;
    const platform = MethodChannelNewApp();
    if (!await platform.consumeReviewRequest()) return;
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const NewAppsPage()),
    );
  }

  /// Con bấm "Xin thêm giờ" trên màn chặn: phụ huynh chọn số phút rồi xác thực.
  Future<void> _checkExtraTime() async {
    if (_challenging || !_guard.isLoaded || !_guard.isConfigured) return;
    _challenging = true;
    try {
      if (!await _guard.device.consumeExtraTimeRequest()) return;
      final overlay = _navigatorKey.currentState?.overlay?.context;
      if (overlay == null || !overlay.mounted) return;
      final minutes = await grantExtraTime(
        overlay,
        platform: const MethodChannelTimeLimit(),
        guard: _guard,
      );
      if (minutes == null || !overlay.mounted) return;
      ScaffoldMessenger.maybeOf(overlay)?.showSnackBar(
        SnackBar(content: Text('Đã thêm $minutes phút cho hôm nay.')),
      );
    } finally {
      _challenging = false;
    }
  }

  /// Dịch vụ chặn vừa đẩy con ra khỏi màn Cài đặt: bắt phụ huynh xác thực,
  /// đúng thì cho vào lại Cài đặt một lúc. Hủy thì thôi, màn Cài đặt vẫn bị chặn.
  Future<void> _checkChallenge() async {
    if (_challenging || !_guard.isLoaded || !_guard.isConfigured) return;
    _challenging = true;
    try {
      if (!await _guard.device.consumeChallenge()) return;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      final ok = await _guard.require(
        'Mở cài đặt hệ thống của SafeFamily',
        promptPin: (session) async =>
            await navigator.push<bool>(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => PinPromptPage(session: session),
              ),
            ) ??
            false,
      );
      if (!ok) return;
      await _guard.device.allowSettings(settingsAllowSeconds);
      final overlay = navigator.overlay?.context;
      if (overlay != null && overlay.mounted) {
        await showDialog<void>(
          context: overlay,
          builder: (context) => AlertDialog(
            title: const Text('Đã xác thực'),
            content: const Text(
              'Bạn có ${settingsAllowSeconds ~/ 60} phút để thay đổi trong '
              'Cài đặt của máy. Hết giờ, màn Cài đặt của SafeFamily bị chặn lại.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đã hiểu'),
              ),
            ],
          ),
        );
      }
    } finally {
      _challenging = false;
    }
  }

  @override
  void dispose() {
    _guard.removeListener(_onGuardChanged);
    _lifecycle?.dispose();
    _voiceLanguage.dispose();
    _themeSettings.dispose();
    if (widget.guard == null) _guard.dispose();
    if (widget.appLock == null) _appLock.dispose();
    if (widget.permissions == null) _permissions.dispose();
    if (widget.setup == null) _setup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ParentGuardScope(
      guard: _guard,
      child: AppLockScope(
        controller: _appLock,
        child: PermissionRegistryScope(
          registry: _permissions,
          child: SetupSettingsScope(
            settings: _setup,
            child: VoiceLanguageScope(
              settings: _voiceLanguage,
              child: ThemeSettingsScope(
                settings: _themeSettings,
                child: ListenableBuilder(
                  listenable: _themeSettings,
                  builder: (context, _) => MaterialApp(
                    navigatorKey: _navigatorKey,
                    title: AppInfo.displayName,
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.light,
                    darkTheme: AppTheme.dark,
                    themeMode: _themeSettings.mode,
                    // Chữ có sẵn của Material (chọn giờ, OK/Hủy…) bằng tiếng Việt.
                    locale: const Locale('vi'),
                    supportedLocales: const [Locale('vi')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    home: _SecurityGate(guard: _guard, setup: _setup),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chưa đặt PIN → màn thiết lập lần đầu; đặt PIN rồi → wizard cấp quyền (1 lần,
/// cờ `setup_done`); xong → app chính.
class _SecurityGate extends StatelessWidget {
  const _SecurityGate({required this.guard, required this.setup});

  final ParentGuard guard;
  final SetupSettings setup;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([guard, setup]),
      builder: (context, _) {
        if (!guard.isLoaded || !setup.isLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!guard.isConfigured) return FirstRunSetupPage(guard: guard);
        if (!setup.isDone) {
          return SetupWizardPage(onFinished: setup.markDone);
        }
        return const AppShell();
      },
    );
  }
}
