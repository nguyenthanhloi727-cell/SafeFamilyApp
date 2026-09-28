// Đổi tên app theo thành viên nhóm (4 người dùng chung source, chỉ khác tên).
//
// Cách dùng (chạy ở thư mục gốc project):
//   dart run tool/rename.dart <hovaten_khong_dau> "<Họ Tên có dấu>"
// Ví dụ:
//   dart run tool/rename.dart nguyenthanhloi "Nguyễn Thành Lợi"
//
// Script đổi:
//   - name trong pubspec.yaml         -> safe_family_app_<hovaten>
//   - applicationId Android           -> com.safefamily.<hovaten>
//   - tên hiển thị trên điện thoại    -> "SafeFamily - <Họ Tên>"
//   - AppInfo.ownerName, AppInfo.applicationId (lib/core/constants/app_info.dart)
//   - import package:... trong test/ theo tên package mới
// Giữ nguyên namespace/package Kotlin để không phải dời MainActivity.
// Import trong lib/ là đường dẫn tương đối nên không cần sửa.
import 'dart:io';

const _pubspec = 'pubspec.yaml';
const _gradle = 'android/app/build.gradle.kts';
const _manifest = 'android/app/src/main/AndroidManifest.xml';
const _appInfo = 'lib/core/constants/app_info.dart';

void main(List<String> args) {
  if (args.length != 2) {
    _fail(
      'Sai cú pháp.\n'
      'Dùng: dart run tool/rename.dart <hovaten_khong_dau> "<Họ Tên có dấu>"',
    );
  }
  final slug = args[0].trim();
  final fullName = args[1].trim();

  // Phải hợp lệ cho cả tên package Dart lẫn một đoạn của applicationId.
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(slug)) {
    _fail(
      'hovaten_khong_dau "$slug" không hợp lệ: chỉ gồm chữ thường a-z, số, '
      'dấu gạch dưới, và bắt đầu bằng chữ. Ví dụ: nguyenthanhloi',
    );
  }
  if (fullName.isEmpty) _fail('Họ Tên không được để trống.');

  if (!File(_pubspec).existsSync()) {
    _fail('Không thấy $_pubspec. Hãy chạy ở thư mục gốc project.');
  }

  final packageName = 'safe_family_app_$slug';
  final applicationId = 'com.safefamily.$slug';
  final displayName = 'SafeFamily - $fullName';

  // Đọc & kiểm tra hết trước, rồi mới ghi — tránh đổi nửa chừng.
  final pubspec = File(_pubspec).readAsStringSync();
  final nameMatch = RegExp(
    r'^name:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (nameMatch == null) _fail('Không tìm thấy dòng "name:" trong $_pubspec.');
  final oldPackageName = nameMatch.group(1)!;

  final edits = <String, String>{
    _pubspec: pubspec.replaceRange(
      nameMatch.start,
      nameMatch.end,
      'name: $packageName',
    ),
    _gradle: _replaceOnce(
      _gradle,
      RegExp(r'applicationId\s*=\s*"[^"]*"'),
      'applicationId = "$applicationId"',
    ),
    _manifest: _replaceOnce(
      _manifest,
      RegExp(r'android:label="[^"]*"'),
      'android:label="${_xmlEscape(displayName)}"',
    ),
    _appInfo: _replaceOnceIn(
      _appInfo,
      _replaceOnce(
        _appInfo,
        RegExp(r"static const ownerName = '(?:[^'\\]|\\.)*';"),
        "static const ownerName = '${_dartEscape(fullName)}';",
      ),
      RegExp(r"static const applicationId = '[^']*';"),
      "static const applicationId = '$applicationId';",
    ),
  };

  if (oldPackageName != packageName) {
    for (final dir in ['test', 'integration_test']) {
      if (!Directory(dir).existsSync()) continue;
      for (final file in Directory(dir).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final content = file.readAsStringSync();
        final updated = content.replaceAll(
          'package:$oldPackageName/',
          'package:$packageName/',
        );
        if (updated != content) edits[file.path] = updated;
      }
    }
  }

  edits.forEach((path, content) => File(path).writeAsStringSync(content));

  stdout.writeln('Đã đổi tên:');
  stdout.writeln('  pubspec name   : $oldPackageName -> $packageName');
  stdout.writeln('  applicationId  : $applicationId');
  stdout.writeln('  tên hiển thị   : $displayName');
  stdout.writeln('  file đã sửa    : ${edits.keys.join(', ')}');

  stdout.writeln('\nĐang chạy flutter pub get...');
  final pubGet = Process.runSync('flutter', ['pub', 'get'], runInShell: true);
  if (pubGet.exitCode != 0) {
    stderr.writeln(pubGet.stdout);
    stderr.writeln(pubGet.stderr);
    _fail('flutter pub get lỗi — chạy tay "flutter pub get" để xem chi tiết.');
  }
  stdout.writeln('Xong. Gỡ app cũ trên máy nếu cần, rồi "flutter run".');
}

/// Thay đúng một chỗ khớp [pattern] trong file [path]; lỗi nếu 0 hoặc >1 chỗ.
String _replaceOnce(String path, RegExp pattern, String replacement) {
  final file = File(path);
  if (!file.existsSync()) _fail('Không thấy file $path.');
  return _replaceOnceIn(path, file.readAsStringSync(), pattern, replacement);
}

/// Như [_replaceOnce] nhưng trên nội dung [content] đã đọc sẵn của [path].
String _replaceOnceIn(
  String path,
  String content,
  RegExp pattern,
  String replacement,
) {
  final count = pattern.allMatches(content).length;
  if (count != 1) {
    _fail('$path: cần đúng 1 chỗ khớp "${pattern.pattern}", thấy $count.');
  }
  return content.replaceFirst(pattern, replacement);
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _dartEscape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');

Never _fail(String message) {
  stderr.writeln('LỖI: $message');
  exit(1);
}
