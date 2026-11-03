import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/profile/data/family_contact.dart';
import 'api_client.dart';
import 'connection_session.dart';
import 'policy_schema.dart';

/// Máy mẹ sửa LUẬT CỦA MÁY CON trên server. Máy mẹ không giữ luật nào cho chính
/// nó: mỗi lần sửa là đọc luật hiện có của máy con, đổi đúng phần cần đổi
/// (danh sách chặn, giới hạn thời gian, danh bạ) rồi ghi lại với số phiên bản đã
/// đọc. Lệch phiên bản (409) thì đọc lại và thử thêm một lần, không ghi đè mù.
class PolicySync {
  PolicySync({
    required this.api,
    required this.session,
    required this.navigatorKey,
  });

  final ApiClient api;
  final ConnectionSession session;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Các app đang bị chặn trên máy con [id] theo luật trên server.
  /// Chưa có luật → rỗng. Lỗi mạng → [ApiException].
  Future<Set<String>> loadBlocked(int id) async =>
      blockedIn((await api.getPolicy(id)).json);

  /// Danh bạ của con [id] theo luật trên server. Chưa có luật → rỗng. Lỗi mạng → [ApiException].
  Future<List<FamilyContact>> loadContacts(int id) async =>
      contactsIn((await api.getPolicy(id)).json);

  /// Danh sách chặn trong chuỗi JSON luật; rỗng nếu thiếu hoặc hỏng.
  static Set<String> blockedIn(String policyJson) {
    try {
      final policy = jsonDecode(policyJson);
      if (policy is! Map) return {};
      final appLock = policy['appLock'];
      final list = appLock is Map ? appLock['blocked'] : null;
      return {if (list is List) ...list.whereType<String>()};
    } catch (_) {
      return {};
    }
  }

  /// `timeLimit` trong chuỗi JSON luật (dạng `TimeLimitConfig.toJson`), `null` nếu chưa có.
  static String? timeLimitIn(String policyJson) {
    try {
      final policy = jsonDecode(policyJson);
      final limit = policy is Map ? policy['timeLimit'] : null;
      return limit is Map ? jsonEncode(limit) : null;
    } catch (_) {
      return null;
    }
  }

  /// Danh bạ trong chuỗi JSON luật; rỗng nếu thiếu hoặc hỏng, mục hỏng bị bỏ qua.
  /// `id` của mỗi liên hệ là vị trí trong luật. Thiếu `sos`: schema < 3 là true, từ 3 là false.
  static List<FamilyContact> contactsIn(String policyJson) {
    try {
      final policy = jsonDecode(policyJson);
      if (policy is! Map) return const [];
      final list = policy['contacts'];
      if (list is! List) return const [];
      final schema = (policy['schemaVersion'] as num?) ?? 1;
      return [
        for (final (i, item) in list.indexed)
          if (item is Map && item['phone'] is String && item['label'] is String)
            FamilyContact(
              id: '$i',
              label: item['label'] as String,
              phone: item['phone'] as String,
              order: i,
              emergency: item['sos'] is bool
                  ? item['sos'] as bool
                  : schema < PolicySchema.version,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Chặn / bỏ chặn một app trên máy con [id]. Trả về danh sách chặn mới;
  /// ném [ApiException] nếu không ghi được.
  Future<Set<String>> setBlocked(int id, String package, bool blocked) async {
    final policy = await _edit(id, (policy) {
      final set = _blockedOf(policy);
      blocked ? set.add(package) : set.remove(package);
      policy['appLock'] = {
        ...?(policy['appLock'] as Map?)?.cast<String, dynamic>(),
        'blocked': set.toList()..sort(),
      };
    });
    return _blockedOf(policy);
  }

  /// Ghi giới hạn thời gian ([timeLimitJson] = `TimeLimitConfig.toJson()`) cho máy con [id].
  Future<void> setTimeLimit(int id, String timeLimitJson) async {
    await _edit(id, (policy) {
      policy['timeLimit'] = jsonDecode(timeLimitJson);
    });
  }

  /// Ghi danh bạ của con [id] (tối đa [PolicySchema.maxContacts] liên hệ, SOS tối đa
  /// [PolicySchema.maxSos], xem [PolicySchema.contactsJson]), giữ nguyên giới hạn thời gian và
  /// danh sách chặn. Trả về danh bạ như server đã lưu; ném [ApiException] nếu không ghi được.
  Future<List<FamilyContact>> setContacts(
    int id,
    List<FamilyContact> contacts,
  ) async {
    final policy = await _edit(id, (policy) {
      policy['contacts'] = PolicySchema.contactsJson(contacts);
      // Luật cũ thiếu `sos` hiểu là "mọi liên hệ đều SOS": phải lên schema 3 để `sos:false` có nghĩa.
      if (((policy['schemaVersion'] as num?) ?? 1) < PolicySchema.version) {
        policy['schemaVersion'] = PolicySchema.version;
      }
    });
    return contactsIn(jsonEncode(policy));
  }

  static Set<String> _blockedOf(Map<String, dynamic> policy) =>
      blockedIn(jsonEncode(policy));

  /// Đọc luật hiện có → [mutate] → ghi lại. Lệch phiên bản thì làm lại một lần.
  Future<Map<String, dynamic>> _edit(
    int id,
    void Function(Map<String, dynamic> policy) mutate,
  ) async {
    ApiException? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      final current = await api.getPolicy(id);
      final policy = current.version == 0
          ? <String, dynamic>{'schemaVersion': PolicySchema.version}
          : Map<String, dynamic>.from(jsonDecode(current.json) as Map);
      mutate(policy);
      try {
        final saved = await api.putPolicy(
          id,
          jsonEncode(policy),
          current.version,
        );
        await session.setPolicyVersion(id, saved.version);
        return policy;
      } on ApiException catch (e) {
        if (!e.isConflict) rethrow;
        last = e;
      }
    }
    throw last!;
  }
}

/// Đưa [PolicySync] xuống cây widget. Không có (test màn lẻ) thì không gửi gì.
class PolicySyncScope extends InheritedWidget {
  const PolicySyncScope({super.key, required this.sync, required super.child});

  final PolicySync sync;

  static PolicySync? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PolicySyncScope>()?.sync;

  @override
  bool updateShouldNotify(PolicySyncScope oldWidget) => sync != oldWidget.sync;
}
