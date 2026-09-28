import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app_nguyenthanhloi/core/constants/app_languages.dart';
import 'package:safe_family_app_nguyenthanhloi/core/settings/voice_language_settings.dart';
import 'package:safe_family_app_nguyenthanhloi/features/alarm/data/speech_recognizer.dart';

void main() {
  group('isLanguageSupported', () {
    test('nhận cả "vi_VN", "vi-VN", "vi"', () {
      for (final ids in [
        ['vi_VN'],
        ['vi-VN'],
        ['vi'],
      ]) {
        expect(isLanguageSupported(ids, AppLanguage.vietnamese), isTrue);
      }
    });

    test('tiếng Trung nhận zh-CN, zh-Hans-CN, cmn-Hans-CN', () {
      expect(isLanguageSupported(['zh-Hans-CN'], AppLanguage.chinese), isTrue);
      expect(isLanguageSupported(['cmn-Hans-CN'], AppLanguage.chinese), isTrue);
    });

    test('thiếu ngôn ngữ → false', () {
      expect(
        isLanguageSupported(['vi-VN', 'en-US'], AppLanguage.japanese),
        isFalse,
      );
    });

    test('máy không báo danh sách (rỗng) → vẫn cho thử', () {
      expect(isLanguageSupported(const [], AppLanguage.korean), isTrue);
    });
  });

  group('VoiceLanguageSettings', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('mặc định Tiếng Việt', () async {
      final settings = VoiceLanguageSettings();
      await settings.load();
      expect(settings.language, AppLanguage.vietnamese);
    });

    test('lưu lựa chọn trên máy', () async {
      await VoiceLanguageSettings().setLanguage(AppLanguage.korean);

      final reopened = VoiceLanguageSettings();
      await reopened.load();
      expect(reopened.language, AppLanguage.korean);
    });
  });
}
