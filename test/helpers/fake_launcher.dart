import 'package:safe_family_app/core/services/external_launcher.dart';

/// Ghi lại thay vì mở app thật.
class FakeLauncher implements ExternalLauncher {
  FakeLauncher({this.succeed = true});

  final bool succeed;
  final dialed = <String>[];
  final emailed = <String>[];
  var youTubeOpened = 0;

  @override
  Future<bool> openDialer(String phone) async {
    dialed.add(phone);
    return succeed;
  }

  @override
  Future<bool> openYouTube() async {
    youTubeOpened++;
    return succeed;
  }

  @override
  Future<bool> openEmail(String email) async {
    emailed.add(email);
    return succeed;
  }
}
