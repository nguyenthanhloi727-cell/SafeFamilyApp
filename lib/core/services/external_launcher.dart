import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mở app ngoài (Điện thoại, mail…). Trả về `false` nếu không mở được —
/// không bao giờ ném lỗi, để giao diện chỉ cần báo SnackBar.
abstract interface class ExternalLauncher {
  /// Mở màn quay số với [phone] soạn sẵn (tel:). Không cần quyền CALL_PHONE.
  Future<bool> openDialer(String phone);

  /// Mở app mail với [email] điền sẵn ở ô người nhận (mailto:).
  Future<bool> openEmail(String email);
}

class UrlExternalLauncher implements ExternalLauncher {
  const UrlExternalLauncher();

  @override
  Future<bool> openDialer(String phone) =>
      _launch(Uri(scheme: 'tel', path: phone), LaunchMode.externalApplication);

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
