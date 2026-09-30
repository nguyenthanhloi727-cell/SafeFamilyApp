import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/core/constants/app_languages.dart';
import 'package:safe_family_app/core/services/system_settings.dart';
import 'package:safe_family_app/core/settings/voice_language_settings.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/alarm/data/alarm_scheduler.dart';
import 'package:safe_family_app/features/alarm/data/speech_recognizer.dart';
import 'package:safe_family_app/features/alarm/domain/alarm_time.dart';
import 'package:safe_family_app/features/alarm/presentation/alarm_page.dart';

/// Micro giả: test tự "nói" bằng cách gọi [say].
class FakeRecognizer implements SpeechRecognizer {
  SpeechInitStatus initStatus = SpeechInitStatus.ready;
  List<String> locales = ['vi-VN', 'en-US', 'ja-JP', 'zh-CN', 'ko-KR'];
  AppLanguage? listenedLanguage;
  int initCalls = 0;

  void Function(String, bool)? _onResult;
  void Function()? _onDone;
  void Function(SpeechError)? _onError;

  void say(String words, {bool isFinal = false}) =>
      _onResult?.call(words, isFinal);
  void fail(SpeechError error) => _onError?.call(error);

  @override
  Future<SpeechInitStatus> initialize() async {
    initCalls++;
    return initStatus;
  }

  @override
  Future<List<String>> supportedLocaleIds() async => locales;

  @override
  Future<void> listen({
    required AppLanguage language,
    required void Function(String words, bool isFinal) onResult,
    required void Function() onDone,
    required void Function(SpeechError error) onError,
  }) async {
    listenedLanguage = language;
    _onResult = onResult;
    _onDone = onDone;
    _onError = onError;
  }

  @override
  Future<void> stop() async => _onDone?.call();

  @override
  Future<void> cancel() async {}
}

class FakeScheduler implements AlarmScheduler {
  AlarmScheduleResult result = AlarmScheduleResult.opened;
  final calls = <(AlarmTime, String)>[];

  @override
  Future<AlarmScheduleResult> setAlarm(
    AlarmTime time, {
    required String label,
  }) async {
    calls.add((time, label));
    return result;
  }
}

class FakeSystemSettings implements SystemSettings {
  int appSettingsOpened = 0;
  int voiceSettingsOpened = 0;

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return true;
  }

  @override
  Future<bool> openVoiceInputSettings() async {
    voiceSettingsOpened++;
    return true;
  }
}

void main() {
  late FakeRecognizer recognizer;
  late FakeScheduler scheduler;
  late FakeSystemSettings systemSettings;
  late VoiceLanguageSettings voiceLanguage;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    recognizer = FakeRecognizer();
    scheduler = FakeScheduler();
    systemSettings = FakeSystemSettings();
    voiceLanguage = VoiceLanguageSettings();
  });

  Future<void> pumpAlarm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400); // 360 × 800 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      VoiceLanguageScope(
        settings: voiceLanguage,
        child: MaterialApp(
          theme: AppTheme.light,
          home: AlarmPage(
            recognizer: recognizer,
            scheduler: scheduler,
            systemSettings: systemSettings,
            clock: () => DateTime(2026, 9, 28, 20, 0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Vùng cuộn của cả màn (ô nhập chữ cũng có Scrollable riêng bên trong).
  final pageScrollable = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;

  Future<void> typeCommand(WidgetTester tester, String text) async {
    final field = find.byKey(const Key('typed-command'));
    await tester.scrollUntilVisible(field, 200, scrollable: pageScrollable);
    await tester.enterText(field, text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel(RegExp('Bắt đầu nói|Dừng nghe')));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: pageScrollable);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String shownTime(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('alarm-time'))).data!;

  testWidgets('gõ câu lệnh → hiện giờ to → Đặt báo thức gửi sang app Đồng hồ', (
    tester,
  ) async {
    await pumpAlarm(tester);

    await typeCommand(tester, 'đặt báo thức 6 giờ 30 sáng');
    expect(shownTime(tester), '06:30');
    expect(find.text('sáng ngày mai'), findsOneWidget);

    await tapVisible(tester, find.text('Đặt báo thức'));

    expect(scheduler.calls.single.$1, const AlarmTime(6, 30));
    expect(scheduler.calls.single.$2, 'SafeFamily');
    expect(find.text('Đã mở app Đồng hồ'), findsOneWidget);
  });

  testWidgets('câu không có giờ → "Không hiểu giờ"', (tester) async {
    await pumpAlarm(tester);

    await typeCommand(tester, 'xin chào');

    expect(find.text('Không hiểu giờ'), findsOneWidget);
    expect(find.byKey(const Key('alarm-time')), findsNothing);
  });

  testWidgets('đang nói hiện chữ theo thời gian thực, câu cuối thì hiểu giờ', (
    tester,
  ) async {
    await pumpAlarm(tester);

    await tapMic(tester);
    expect(recognizer.initCalls, 1, reason: 'xin quyền lúc bấm micro lần đầu');
    expect(recognizer.listenedLanguage, AppLanguage.vietnamese);
    expect(find.text('Đang nghe… chạm để dừng'), findsOneWidget);

    recognizer.say('đặt báo thức 7 giờ');
    await tester.pump();
    expect(find.text('“đặt báo thức 7 giờ”'), findsOneWidget);

    recognizer.say('đặt báo thức 7 giờ tối', isFinal: true);
    await tester.pumpAndSettle();
    expect(shownTime(tester), '19:00');
    expect(find.text('Chạm micro để nói'), findsOneWidget);
  });

  testWidgets(
    'từ chối quyền micro → giải thích + Mở Cài đặt; cấp lại rồi Thử lại',
    (tester) async {
      recognizer.initStatus = SpeechInitStatus.permissionDenied;
      await pumpAlarm(tester);

      await tapMic(tester);
      expect(find.text('Chưa có quyền dùng micro'), findsOneWidget);

      await tester.tap(find.text('Mở Cài đặt'));
      await tester.pump();
      expect(systemSettings.appSettingsOpened, 1);

      // Người dùng cấp quyền trong Cài đặt rồi quay lại bấm Thử lại.
      recognizer.initStatus = SpeechInitStatus.ready;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có quyền dùng micro'), findsNothing);
      expect(find.text('Đang nghe… chạm để dừng'), findsOneWidget);
    },
  );

  testWidgets('máy không có dịch vụ nhận giọng nói → báo rõ, không crash', (
    tester,
  ) async {
    recognizer.initStatus = SpeechInitStatus.unavailable;
    await pumpAlarm(tester);

    await tapMic(tester);

    expect(find.text('Máy không có dịch vụ nhận giọng nói'), findsOneWidget);
  });

  testWidgets('máy thiếu gói ngôn ngữ → "máy chưa có gói … tiếng Nhật"', (
    tester,
  ) async {
    await voiceLanguage.setLanguage(AppLanguage.japanese);
    recognizer.locales = ['vi-VN', 'en_US'];
    await pumpAlarm(tester);

    await tapMic(tester);

    expect(
      find.text('Máy chưa có gói nhận giọng nói tiếng Nhật'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mở cài đặt giọng nói'));
    await tester.pump();
    expect(systemSettings.voiceSettingsOpened, 1);
  });

  testWidgets('lỗi khi đang nghe → báo, không crash', (tester) async {
    await pumpAlarm(tester);
    await tapMic(tester);

    recognizer.fail(SpeechError.noSpeech);
    await tester.pumpAndSettle();

    expect(find.text('Không nghe rõ'), findsOneWidget);
    expect(find.text('Chạm micro để nói'), findsOneWidget);
  });

  testWidgets('không có app Đồng hồ → báo lỗi + gợi ý đặt tay', (tester) async {
    scheduler.result = AlarmScheduleResult.noClockApp;
    await pumpAlarm(tester);

    await typeCommand(tester, '6 giờ 30 sáng');
    await tapVisible(tester, find.text('Đặt báo thức'));

    expect(
      find.text('Máy không có app Đồng hồ nhận lệnh đặt báo thức'),
      findsOneWidget,
    );
    expect(find.textContaining('đặt báo thức tay lúc 06:30'), findsOneWidget);
    expect(find.text('Đã mở app Đồng hồ'), findsNothing);
  });

  testWidgets('đổi ngôn ngữ bằng chip → lưu lại và nghe bằng ngôn ngữ mới', (
    tester,
  ) async {
    await pumpAlarm(tester);

    await tester.tap(find.byTooltip('Đổi ngôn ngữ giọng nói'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(voiceLanguage.language, AppLanguage.english);
    expect(find.text('Hãy nói: “Set an alarm for 7:30 am”'), findsOneWidget);

    await tapMic(tester);
    expect(recognizer.listenedLanguage, AppLanguage.english);

    // Mở lại app (settings mới) vẫn nhớ English.
    final reopened = VoiceLanguageSettings();
    await reopened.load();
    expect(reopened.language, AppLanguage.english);
  });
}
