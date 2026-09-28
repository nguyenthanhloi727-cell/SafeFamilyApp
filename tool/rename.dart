// Đổi app sang tên thành viên nhóm (4 người dùng chung source, chỉ khác tên).
//
// Cách dùng (ở thư mục gốc project — hoặc bấm đúp tool\doi-ten.bat trên Windows):
//   dart run tool/rename.dart                       → chọn tên trong danh sách nhóm
//   dart run tool/rename.dart hongocphu             → lấy họ tên từ assets/team/members.json
//   dart run tool/rename.dart nguyenvana "Nguyễn Văn A"   → người ngoài nhóm
//   dart run tool/rename.dart --reset               → trả về tên mặc định của repo
//
// Script đổi:
//   - name trong pubspec.yaml            -> safe_family_app_<id>
//   - applicationId Android              -> com.safefamily.<id>
//   - namespace Android + thư mục/package của MainActivity.kt
//                                        -> com.safefamily.safe_family_app_<id>
//   - tên hiển thị trên điện thoại       -> "SafeFamily - <Họ Tên>"
//   - AppInfo.ownerName, AppInfo.applicationId (lib/core/constants/app_info.dart)
//   - import package:... trong test/ theo tên package mới
// Import trong lib/ là đường dẫn tương đối nên không cần sửa.
import 'dart:convert';
import 'dart:io';

/// Tên mặc định của repo (thành viên giữ repo). Commit luôn để tên này.
const defaultId = 'nguyenthanhloi';
const defaultName = 'Nguyễn Thành Lợi';

const _pubspec = 'pubspec.yaml';
const _gradle = 'android/app/build.gradle.kts';
const _manifest = 'android/app/src/main/AndroidManifest.xml';
const _appInfo = 'lib/core/constants/app_info.dart';
const _members = 'assets/team/members.json';
const _kotlinRoot = 'android/app/src/main/kotlin/com/safefamily';

void main(List<String> args) {
  if (!File(_pubspec).existsSync()) {
    _fail('Không thấy $_pubspec. Hãy chạy ở thư mục gốc project.');
  }
  final (slug, fullName) = _resolveTarget(args);

  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(slug)) {
    _fail(
      'id "$slug" không hợp lệ: chỉ gồm chữ thường a-z, số, dấu gạch dưới, '
      'bắt đầu bằng chữ. Ví dụ: nguyenvana',
    );
  }
  if (fullName.isEmpty) _fail('Họ Tên không được để trống.');

  final packageName = 'safe_family_app_$slug';
  final applicationId = 'com.safefamily.$slug';
  final namespace = 'com.safefamily.$packageName';
  final displayName = 'SafeFamily - $fullName';

  // Đọc & kiểm tra hết trước, rồi mới ghi — tránh đổi nửa chừng.
  final pubspec = File(_pubspec).readAsStringSync();
  final nameMatch = RegExp(
    r'^name:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (nameMatch == null) _fail('Không tìm thấy dòng "name:" trong $_pubspec.');
  final oldPackageName = nameMatch.group(1)!;

  final gradle = _read(_gradle);
  final namespaceMatch = RegExp(
    r'namespace\s*=\s*"com\.safefamily\.([a-z0-9_]+)"',
  ).firstMatch(gradle);
  if (namespaceMatch == null) _fail('Không tìm thấy namespace trong $_gradle.');
  final oldSegment = namespaceMatch.group(1)!;
  final oldActivity = File('$_kotlinRoot/$oldSegment/MainActivity.kt');
  if (!oldActivity.existsSync()) _fail('Không thấy ${oldActivity.path}.');

  final edits = <String, String>{
    _pubspec: pubspec.replaceRange(
      nameMatch.start,
      nameMatch.end,
      'name: $packageName',
    ),
    _gradle: _replaceOnceIn(
      _gradle,
      _replaceOnceIn(
        _gradle,
        gradle,
        RegExp(r'applicationId\s*=\s*"[^"]*"'),
        'applicationId = "$applicationId"',
      ),
      RegExp(r'namespace\s*=\s*"[^"]*"'),
      'namespace = "$namespace"',
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

  // MainActivity.kt: sửa dòng package, dời sang thư mục theo namespace mới.
  final activity = _replaceOnceIn(
    oldActivity.path,
    oldActivity.readAsStringSync(),
    RegExp(r'^package\s+[\w.]+', multiLine: true),
    'package $namespace',
  );

  edits.forEach((path, content) => File(path).writeAsStringSync(content));
  final newActivity = File('$_kotlinRoot/$packageName/MainActivity.kt');
  newActivity.parent.createSync(recursive: true);
  newActivity.writeAsStringSync(activity);
  if (oldSegment != packageName) {
    oldActivity.deleteSync();
    final oldDir = oldActivity.parent;
    if (oldDir.listSync().isEmpty) oldDir.deleteSync();
  }

  stdout.writeln('\nĐã đổi tên:');
  stdout.writeln('  tên trên điện thoại : $displayName');
  stdout.writeln('  applicationId       : $applicationId');
  stdout.writeln('  pubspec name        : $oldPackageName -> $packageName');
  stdout.writeln('  namespace Android   : $namespace');
  stdout.writeln('  số file đã sửa      : ${edits.length + 1}');

  stdout.writeln('\nĐang chạy flutter pub get...');
  final pubGet = Process.runSync('flutter', ['pub', 'get'], runInShell: true);
  if (pubGet.exitCode != 0) {
    stderr.writeln(pubGet.stdout);
    stderr.writeln(pubGet.stderr);
    _fail('flutter pub get lỗi — chạy tay "flutter pub get" để xem chi tiết.');
  }
  stdout.writeln('Xong. Chạy "flutter run" để cài app mang tên mới.');
  if (slug != defaultId) {
    stdout.writeln(
      'Nhớ: trước khi commit chạy "dart run tool/rename.dart --reset".',
    );
  }
}

/// Xác định (id, Họ Tên) từ tham số, hoặc hỏi chọn trong danh sách nhóm.
(String, String) _resolveTarget(List<String> args) {
  if (args.length == 1 && args.first == '--reset') {
    return (defaultId, defaultName);
  }
  if (args.length == 2) return (args[0].trim(), args[1].trim());

  final members = _loadMembers();
  if (args.length == 1) {
    final id = args.first.trim();
    final name = members[id];
    if (name == null) {
      _fail(
        'Không có id "$id" trong $_members. Có: ${members.keys.join(', ')}.\n'
        'Người ngoài nhóm: dart run tool/rename.dart <id> "<Họ Tên>"',
      );
    }
    return (id, name);
  }
  if (args.isNotEmpty) {
    _fail(
      'Sai cú pháp. Dùng: dart run tool/rename.dart  |  <id>  |  '
      '<id> "<Họ Tên>"  |  --reset',
    );
  }

  final entries = members.entries.toList();
  stdout.writeln('Chọn thành viên để đổi app sang tên người đó:');
  for (final (i, e) in entries.indexed) {
    stdout.writeln('  ${i + 1}. ${e.value}  (${e.key})');
  }
  stdout.write('Gõ số rồi Enter: ');
  final choice = int.tryParse(stdin.readLineSync()?.trim() ?? '');
  if (choice == null || choice < 1 || choice > entries.length) {
    _fail('Lựa chọn không hợp lệ.');
  }
  final picked = entries[choice - 1];
  return (picked.key, picked.value);
}

/// id → Họ Tên, theo đúng thứ tự trong assets/team/members.json.
Map<String, String> _loadMembers() {
  try {
    final list = jsonDecode(_read(_members)) as List<Object?>;
    return {
      for (final m in list.cast<Map<String, Object?>>())
        m['id']! as String: m['fullName']! as String,
    };
  } catch (e) {
    _fail('Không đọc được $_members: $e');
  }
}

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) _fail('Không thấy file $path.');
  return file.readAsStringSync();
}

/// Thay đúng một chỗ khớp [pattern] trong file [path]; lỗi nếu 0 hoặc >1 chỗ.
String _replaceOnce(String path, RegExp pattern, String replacement) =>
    _replaceOnceIn(path, _read(path), pattern, replacement);

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
