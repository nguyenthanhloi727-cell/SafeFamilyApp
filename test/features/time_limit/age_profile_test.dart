import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/settings/theme_settings.dart';
import 'package:safe_family_app/features/time_limit/domain/age_profile.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('AgeProfile.applyTo', () {
    test('đặt tổng theo ngày thường/cuối tuần và giờ ngủ cả tuần', () {
      final config = AgeProfile.age6to8.applyTo(TimeLimitConfig());
      expect(config.enabled, isTrue);
      expect(config.bedtimeEnabled, isTrue);
      expect(config.total, [60, 60, 60, 60, 60, 120, 120]);
      expect(config.bedtime, hasLength(7));
      expect(config.bedtime, everyElement(AgeProfile.age6to8.bedtime));
    });

    test('giữ nguyên giới hạn app, giờ học và app học', () {
      final base = TimeLimitConfig(
        apps: {'com.google.android.youtube': List<int?>.filled(7, 30)},
        studyEnabled: true,
        studyApps: {'com.example.dict'},
      );
      final config = AgeProfile.age9to12.applyTo(base);
      expect(config.apps, base.apps);
      expect(config.studyEnabled, isTrue);
      expect(config.studyApps, {'com.example.dict'});
      expect(config.total.first, 90);
      expect(config.total.last, 180);
    });

    test('giờ ngủ 20:00–06:30 chặn 23:30 và 06:00, mở lại 06:30', () {
      final config = AgeProfile.age6to8.applyTo(TimeLimitConfig());
      expect(config.inBedtime(DateTime(2026, 10, 21, 23, 30)), isTrue);
      expect(config.inBedtime(DateTime(2026, 10, 22, 6, 0)), isTrue);
      expect(config.inBedtime(DateTime(2026, 10, 22, 6, 30)), isFalse);
      expect(config.inBedtime(DateTime(2026, 10, 22, 19, 59)), isFalse);
    });

    test('JSON giữ nguyên sau khi áp mẫu', () {
      final config = AgeProfile.age9to12.applyTo(TimeLimitConfig());
      final back = TimeLimitConfig.fromJson(config.toJson());
      expect(back.total, config.total);
      expect(back.bedtime, config.bedtime);
    });
  });

  group('ThemeSettings', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('mặc định sáng, lưu và đọc lại chế độ tối', () async {
      final settings = ThemeSettings();
      await settings.load();
      expect(settings.mode, ThemeMode.light);

      await settings.setMode(ThemeMode.dark);
      final reloaded = ThemeSettings();
      await reloaded.load();
      expect(reloaded.mode, ThemeMode.dark);
    });
  });
}
