import 'dart:convert';

import '../permissions/permission_registry.dart';
import 'api_client.dart';

/// "vừa xong", "5 phút trước"... cho mốc [t] (giờ máy này).
String agoText(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inHours < 1) return '${d.inMinutes} phút trước';
  if (d.inDays < 1) return '${d.inHours} giờ trước';
  return '${d.inDays} ngày trước';
}

/// Tên quyền hiển thị cho mẹ từ id máy con báo; id lạ (máy con bản mới hơn) thì hiện nguyên id.
String permissionLabel(String id) {
  for (final p in AppPermission.values) {
    if (p.id == id) return p.label;
  }
  return id;
}

/// Câu hiển thị cho mẹ về một yêu cầu của con, ví dụ "Con xin thêm 15 phút".
String requestLabel(ChildRequestInfo r) => switch (r.kind) {
  RequestKind.extraTime =>
    r.minutes == null ? 'Con xin thêm giờ' : 'Con xin thêm ${r.minutes} phút',
  RequestKind.studyDone => 'Con báo đã học xong',
  _ => 'Yêu cầu của con',
};

/// Câu hiển thị cho mẹ về một cảnh báo của máy con. `detail` chỉ là mã/số ngắn do máy con gửi nên
/// được diễn giải ở đây; loại hoặc mã lạ (máy con bản mới hơn) thì hiện nguyên chữ, không đoán.
String alertLabel(AlertInfo a) {
  final d = a.detail;
  switch (a.kind) {
    case AlertKind.timeChanged:
      final minutes = int.tryParse(d ?? '');
      if (minutes == null || minutes == 0) return 'Giờ trên máy con bị chỉnh';
      final dir = minutes > 0 ? 'nhanh' : 'chậm';
      return 'Giờ trên máy con bị chỉnh $dir hơn ${minutes.abs()} phút';
    case AlertKind.appUninstallAttempt:
      return d == 'authorized'
          ? 'Đã mở quy trình gỡ SafeFamily (có nhập khóa phụ huynh)'
          : 'Có người mở màn cài đặt của SafeFamily khi chưa qua khóa phụ huynh';
    case AlertKind.accessibilityOff:
      return 'Dịch vụ Trợ năng của SafeFamily đã bị tắt';
    case AlertKind.deviceAdminOff:
      return 'Quyền Quản trị thiết bị của SafeFamily đã bị tắt';
    case AlertKind.permissionMissing:
      return d == null
          ? 'Máy con vừa mất một quyền'
          : 'Máy con vừa mất quyền: ${permissionLabel(d)}';
    case AlertKind.offline:
      final hours = int.tryParse(d ?? '');
      return hours == null || hours < 1
          ? 'Máy con mất kết nối'
          : 'Máy con mất kết nối hơn $hours giờ';
    default:
      return a.kind;
  }
}

/// Mô tả ngắn một lệnh mẹ đã gửi, ví dụ "Mở tạm com.zing.zalo 15 phút".
String commandLabel(CommandInfo c) {
  Map<String, dynamic> p = const {};
  try {
    final decoded = jsonDecode(c.payloadJson);
    if (decoded is Map<String, dynamic>) p = decoded;
  } catch (_) {
    // Payload hỏng: chỉ hiện tên lệnh.
  }
  final pkg = p['package'] as String?;
  final minutes = p['minutes'] as int?;
  final forMinutes = minutes == null ? '' : ' $minutes phút';
  return switch (c.type) {
    'pause' =>
      minutes == null || minutes == 0
          ? 'Tạm dừng máy cho tới khi tắt'
          : 'Tạm dừng máy$forMinutes',
    'unpause' => 'Tiếp tục dùng máy',
    'lock' => 'Khóa máy$forMinutes',
    'unlock' => 'Mở khóa máy',
    'study_start' => 'Bắt đầu giờ học$forMinutes',
    'study_stop' => 'Dừng giờ học',
    'extra_time_grant' => 'Cộng$forMinutes giờ dùng máy hôm nay',
    'study_approve' => 'Duyệt đã học xong',
    'study_reject' => 'Từ chối đã học xong',
    'disable_limit_today' => 'Tắt giới hạn hôm nay',
    'enable_limit_today' => 'Bật lại giới hạn',
    'app_unlock_temp' => 'Mở tạm ${pkg ?? 'ứng dụng'}$forMinutes',
    'app_relock' => 'Chặn lại ${pkg ?? 'ứng dụng'}',
    'app_block' => 'Chặn ${pkg ?? 'ứng dụng'}',
    'app_allow' => 'Cho phép ${pkg ?? 'ứng dụng'}',
    _ => c.type,
  };
}
