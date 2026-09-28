import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';

import '../domain/alarm_time.dart';

enum AlarmScheduleResult {
  /// Đã mở app Đồng hồ với giờ điền sẵn.
  opened,

  /// Máy không có app nào nhận Intent SET_ALARM.
  noClockApp,

  failed,
}

/// Đặt báo thức vào app Đồng hồ của máy (app KHÔNG tự báo thức).
abstract interface class AlarmScheduler {
  Future<AlarmScheduleResult> setAlarm(AlarmTime time, {required String label});
}

/// Intent chuẩn của Android `AlarmClock.ACTION_SET_ALARM` — chạy với mọi app
/// Đồng hồ hỗ trợ chuẩn này, không viết riêng cho hãng nào.
class AndroidAlarmScheduler implements AlarmScheduler {
  const AndroidAlarmScheduler();

  static const action = 'android.intent.action.SET_ALARM';

  @override
  Future<AlarmScheduleResult> setAlarm(
    AlarmTime time, {
    required String label,
  }) async {
    final intent = AndroidIntent(
      action: action,
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': time.hour,
        'android.intent.extra.alarm.MINUTES': time.minute,
        'android.intent.extra.alarm.MESSAGE': label,
        // Mở giao diện app Đồng hồ cho người dùng thấy và xác nhận.
        'android.intent.extra.alarm.SKIP_UI': false,
      },
    );
    try {
      if (await intent.canResolveActivity() != true) {
        return AlarmScheduleResult.noClockApp;
      }
      await intent.launch();
      return AlarmScheduleResult.opened;
    } catch (error) {
      debugPrint('Không gửi được SET_ALARM: $error');
      return AlarmScheduleResult.failed;
    }
  }
}
