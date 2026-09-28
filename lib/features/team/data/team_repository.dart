import 'dart:convert';

import 'package:flutter/services.dart';

import 'team_member.dart';

/// Nguồn dữ liệu tab Nhóm: danh sách thành viên + ảnh cố định có sẵn.
abstract interface class TeamRepository {
  /// Theo đúng thứ tự trong file.
  Future<List<TeamMember>> loadMembers();

  /// Đường dẫn các ảnh cố định đang có trong app, ví dụ `assets/team/abc.jpg`.
  Future<Set<String>> loadPhotoAssets();
}

/// Đọc từ assets đóng gói trong app.
class AssetTeamRepository implements TeamRepository {
  AssetTeamRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const membersPath = 'assets/team/members.json';

  /// Ảnh cố định của thành viên [id].
  static String photoAssetPath(String id) => 'assets/team/$id.jpg';

  final AssetBundle _bundle;

  @override
  Future<List<TeamMember>> loadMembers() async {
    final raw = await _bundle.loadString(membersPath);
    return parseTeamMembers(raw);
  }

  @override
  Future<Set<String>> loadPhotoAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    return manifest
        .listAssets()
        .where(
          (path) => path.startsWith('assets/team/') && path.endsWith('.jpg'),
        )
        .toSet();
  }
}

/// Tách riêng để test được mà không cần AssetBundle.
List<TeamMember> parseTeamMembers(String json) {
  return [
    for (final item in jsonDecode(json) as List<Object?>)
      TeamMember.fromJson(item! as Map<String, Object?>),
  ];
}
