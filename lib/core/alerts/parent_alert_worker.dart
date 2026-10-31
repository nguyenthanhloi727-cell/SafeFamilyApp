import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../network/api_client.dart';
import '../network/connection_session.dart';
import 'geofence_alerts.dart';
import 'new_app_alerts.dart';
import 'request_alerts.dart';
import 'tamper_alerts.dart';

const _kTask = 'geofence_alert_check';
const _kUnique = 'safefamily_geofence_alerts';

/// Điểm vào của tác vụ nền (chạy ở isolate riêng khi app mẹ đã đóng).
/// WorkManager tối thiểu 15 phút nên cảnh báo trễ hơn lúc app đang mở.
@pragma('vm:entry-point')
void parentAlertDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _kTask) return true;
    try {
      final session = ConnectionSession();
      await session.load();
      if (session.mode != ConnectionMode.parent || !session.isParentLoggedIn) {
        return true;
      }
      final api = ApiClient(session: session);
      // Bốn việc độc lập: lỗi mạng ở việc này không được làm mất việc kia.
      Object? failure;
      try {
        await _show(
          [
            for (final a in await GeofenceAlertChecker(api).check())
              (title: a.title, body: a.body),
          ],
          'geofence_alerts',
          'Cảnh báo vị trí của con',
        );
      } on ApiException catch (e) {
        failure = e;
      }
      try {
        await _show(
          [
            for (final a in await ChildRequestAlertChecker(api).check())
              (title: a.title, body: a.body),
          ],
          'child_requests',
          'Yêu cầu của con',
        );
      } on ApiException catch (e) {
        failure ??= e;
      }
      try {
        await _show(
          [
            for (final a in await NewAppAlertChecker(api).check())
              (title: a.title, body: a.body),
          ],
          'new_apps',
          'App mới cài trên máy con',
        );
      } on ApiException catch (e) {
        failure ??= e;
      }
      try {
        await _show(
          [
            for (final a in await TamperAlertChecker(api).check())
              (title: a.title, body: a.body),
          ],
          'tamper_alerts',
          'Cảnh báo máy con bị can thiệp hoặc mất kết nối',
        );
      } on ApiException catch (e) {
        failure ??= e;
      }
      if (failure != null) throw failure;
      return true;
    } on ApiException catch (e) {
      // Mất mạng thì để lượt sau; lỗi khác (hết phiên...) đừng thử lại dồn dập.
      return !e.isNetwork;
    } catch (_) {
      return true;
    }
  });
}

Future<void> _show(
  List<({String title, String body})> alerts,
  String channelId,
  String channelName,
) async {
  if (alerts.isEmpty) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  var id = DateTime.now().millisecondsSinceEpoch % 1000000;
  for (final a in alerts) {
    await plugin.show(
      id: id++,
      title: a.title,
      body: a.body,
      notificationDetails: details,
    );
  }
}

/// Bật/tắt tác vụ nền theo vai trò. Chỉ Android; máy khác bỏ qua.
class ParentAlertWorker {
  const ParentAlertWorker._();

  static Future<void> sync(ConnectionSession session) async {
    if (!Platform.isAndroid) return;
    try {
      final wm = Workmanager();
      await wm.initialize(parentAlertDispatcher);
      if (session.mode == ConnectionMode.parent && session.isParentLoggedIn) {
        await wm.registerPeriodicTask(
          _kUnique,
          _kTask,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } else {
        await wm.cancelByUniqueName(_kUnique);
      }
    } catch (_) {
      // Không đặt được lịch nền: màn giám sát vẫn tự làm mới khi mở.
    }
  }
}
