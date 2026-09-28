import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_languages.dart';

/// Ngôn ngữ giọng nói đang chọn — dùng chung cho màn Báo thức và Cài đặt,
/// lưu trên máy. Mặc định Tiếng Việt.
class VoiceLanguageSettings extends ChangeNotifier {
  VoiceLanguageSettings({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const storageKey = 'settings.voice_language';

  final SharedPreferencesAsync _prefs;
  AppLanguage _language = AppLanguage.defaultVoice;

  AppLanguage get language => _language;

  Future<void> load() async {
    try {
      _language = AppLanguage.fromLocaleTag(await _prefs.getString(storageKey));
      notifyListeners();
    } catch (_) {
      // Không đọc được thì giữ mặc định.
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (language == _language) return;
    _language = language;
    notifyListeners();
    await _prefs.setString(storageKey, language.localeTag);
  }
}

/// Đưa [VoiceLanguageSettings] xuống cây widget (đặt ở trên MaterialApp).
class VoiceLanguageScope extends InheritedNotifier<VoiceLanguageSettings> {
  const VoiceLanguageScope({
    super.key,
    required VoiceLanguageSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static VoiceLanguageSettings of(BuildContext context) {
    final settings = maybeOf(context);
    assert(settings != null, 'Thiếu VoiceLanguageScope phía trên.');
    return settings!;
  }

  static VoiceLanguageSettings? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<VoiceLanguageScope>()
      ?.notifier;
}
