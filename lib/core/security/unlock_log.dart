import 'dart:convert';

import 'secure_store.dart';

enum UnlockMethod {
  fingerprint('Vân tay'),
  face('Khuôn mặt'),

  /// Máy có cả vân tay lẫn khuôn mặt: Android không cho biết đã dùng cái nào.
  biometric('Vân tay/khuôn mặt'),
  pin('Mã PIN');

  const UnlockMethod(this.label);
  final String label;
}

enum UnlockResult {
  success('Thành công'),
  failure('Thất bại'),
  canceled('Đã hủy');

  const UnlockResult(this.label);
  final String label;
}

class UnlockLogEntry {
  const UnlockLogEntry({
    required this.time,
    required this.action,
    required this.method,
    required this.result,
  });

  final DateTime time;

  /// Thao tác cần mở khóa, ví dụ "Sửa danh bạ".
  final String action;
  final UnlockMethod method;
  final UnlockResult result;

  Map<String, Object> toJson() => {
    't': time.millisecondsSinceEpoch,
    'a': action,
    'm': method.name,
    'r': result.name,
  };

  static UnlockLogEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return UnlockLogEntry(
        time: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
        action: json['a'] as String,
        method: UnlockMethod.values.byName(json['m'] as String),
        result: UnlockResult.values.byName(json['r'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Nhật ký mở khóa: lưu trên máy (kho bảo mật), mới nhất trước, tối đa [maxEntries].
class UnlockLog {
  UnlockLog(this._store);

  static const storageKey = 'guard.unlock_log';
  static const maxEntries = 200;

  final SecureStore _store;

  Future<List<UnlockLogEntry>> entries() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List<Object?>)
          ?UnlockLogEntry.fromJson(item),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> add(UnlockLogEntry entry) async {
    final all = [entry, ...await entries()];
    final kept = all.length > maxEntries ? all.sublist(0, maxEntries) : all;
    await _store.write(
      storageKey,
      jsonEncode([for (final e in kept) e.toJson()]),
    );
  }

  Future<void> clear() => _store.delete(storageKey);
}
