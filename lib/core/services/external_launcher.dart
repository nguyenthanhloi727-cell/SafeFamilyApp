import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mở app ngoài (Điện thoại, YouTube…). Trả về `false` nếu không mở được —
/// không bao giờ ném lỗi, để giao diện chỉ cần báo SnackBar.
abstract interface class ExternalLauncher {
  /// Mở màn quay số với [phone] soạn sẵn (tel:). Không cần quyền CALL_PHONE.
  Future<bool> openDialer(String phone);

  /// Mở YouTube: ưu tiên app YouTube, không có thì mở trình duyệt.
  Future<bool> openYouTube();

  /// Mở app mail với [email] điền sẵn ở ô người nhận (mailto:).
  Future<bool> openEmail(String email);
}

class UrlExternalLauncher implements ExternalLauncher {
  const UrlExternalLauncher();

  static final youTubeUri = Uri.parse('https://www.youtube.com');

  @override
  Future<bool> openDialer(String phone) =>
      _launch(Uri(scheme: 'tel', path: phone), LaunchMode.externalApplication);

  @override
  Future<bool> openYouTube() async {
    // Chỉ mở app không phải trình duyệt (app YouTube) nếu có…
    if (await _launch(youTubeUri, LaunchMode.externalNonBrowserApplication)) {
      return true;
    }
    // …không có thì để hệ thống mở bằng trình duyệt.
    return _launch(youTubeUri, LaunchMode.externalApplication);
  }

  @override
  Future<bool> openEmail(String email) => _launch(
    Uri(scheme: 'mailto', path: email),
    LaunchMode.externalApplication,
  );

  Future<bool> _launch(Uri uri, LaunchMode mode) async {
    try {
      return await launchUrl(uri, mode: mode);
    } catch (error) {
      debugPrint('Không mở được $uri: $error');
      return false;
    }
  }
}
