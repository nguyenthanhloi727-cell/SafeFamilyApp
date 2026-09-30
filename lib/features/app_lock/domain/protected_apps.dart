import '../../../core/constants/app_info.dart';

/// App không bao giờ được chặn: SafeFamily, Điện thoại, Cài đặt, trình
/// khởi động (launcher) — chặn nhầm thì khóa luôn cả phụ huynh.
///
/// Danh sách thật hỏi từ máy lúc chạy (app nào nhận lệnh gọi điện, mở Cài
/// đặt, màn hình chính). [fallback] là lưới an toàn khi không hỏi được.
abstract final class ProtectedApps {
  static const fallback = {
    AppInfo.applicationId,
    // Cài đặt
    'com.android.settings',
    // Điện thoại
    'com.android.dialer',
    'com.google.android.dialer',
    'com.android.phone',
    'com.android.server.telecom',
    'com.samsung.android.dialer',
    'com.android.incallui',
    // Trình khởi động
    'com.android.launcher',
    'com.android.launcher3',
    'com.google.android.apps.nexuslauncher',
    'com.miui.home',
    'com.mi.android.globallauncher',
    'com.sec.android.app.launcher',
    'com.oppo.launcher',
    'com.bbk.launcher2',
    'com.huawei.android.launcher',
    // Thanh trạng thái / màn khóa
    'com.android.systemui',
  };

  /// [resolved]: package máy trả về cho Điện thoại / Cài đặt / launcher.
  static bool isProtected(String packageName, Set<String> resolved) =>
      fallback.contains(packageName) || resolved.contains(packageName);
}
