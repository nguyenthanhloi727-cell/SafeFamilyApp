/// Số lần nhập sai PIN liên tiếp được phép trước khi bị khóa.
const pinAttemptsBeforeLock = 5;

/// Khóa lần đầu 30 giây; mỗi lần sai tiếp theo gấp đôi, tối đa 30 phút.
const firstLockDuration = Duration(seconds: 30);
const maxLockDuration = Duration(minutes: 30);

/// Thời gian khóa sau lần sai thứ [consecutiveFailures]; `null` = chưa khóa.
///
/// 1–4 → không khóa · 5 → 30 giây · 6 → 1 phút · 7 → 2 phút · … · tối đa 30 phút.
Duration? lockDurationAfter(int consecutiveFailures) {
  if (consecutiveFailures < pinAttemptsBeforeLock) return null;
  final extra = consecutiveFailures - pinAttemptsBeforeLock;
  if (extra >= 16) return maxLockDuration; // tránh tràn số
  final duration = firstLockDuration * (1 << extra);
  return duration > maxLockDuration ? maxLockDuration : duration;
}

/// Một lần khóa nhập PIN đang có hiệu lực, lưu kèm các mốc để tính lại thời
/// gian còn lại mà con không rút ngắn được bằng cách đổi giờ hệ thống.
class LockRecord {
  const LockRecord({
    required this.duration,
    required this.lockedAtWall,
    this.elapsedAtLock,
    this.bootCount,
  });

  /// Thời gian khóa (còn lại tính từ [elapsedAtLock] / [lockedAtWall]).
  final Duration duration;

  /// Giờ treo tường lúc khóa (đổi giờ được → chỉ dùng làm phương án dự phòng).
  final DateTime lockedAtWall;

  /// `elapsedRealtime` lúc khóa; `null` nếu máy không đọc được.
  final Duration? elapsedAtLock;
  final int? bootCount;

  Map<String, Object?> toJson() => {
    'durationMs': duration.inMilliseconds,
    'wallMs': lockedAtWall.millisecondsSinceEpoch,
    'elapsedMs': elapsedAtLock?.inMilliseconds,
    'boot': bootCount,
  };

  static LockRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final duration = json['durationMs'];
    final wall = json['wallMs'];
    if (duration is! int || wall is! int) return null;
    final elapsed = json['elapsedMs'];
    final boot = json['boot'];
    return LockRecord(
      duration: Duration(milliseconds: duration),
      lockedAtWall: DateTime.fromMillisecondsSinceEpoch(wall),
      elapsedAtLock: elapsed is int ? Duration(milliseconds: elapsed) : null,
      bootCount: boot is int ? boot : null,
    );
  }
}

/// Thời gian khóa còn lại. Không bao giờ ngắn hơn thực tế vì đổi giờ:
///
/// - Cùng lần khởi động: dùng đồng hồ elapsed (đổi giờ hệ thống không ảnh hưởng).
/// - Máy đã khởi động lại: coi như khóa bắt đầu từ lúc máy bật, tức là chỉ có
///   thể lâu hơn thực tế một chút, không thể ngắn hơn.
/// - Không đọc được elapsed: dùng giờ treo tường; giờ lùi về trước lúc khóa thì
///   tính đủ thời gian khóa.
Duration remainingLock(
  LockRecord lock, {
  required DateTime now,
  Duration? elapsedNow,
  int? bootCountNow,
}) {
  final Duration remaining;
  if (elapsedNow != null && lock.elapsedAtLock != null) {
    final sameBoot =
        bootCountNow != null &&
        bootCountNow != -1 &&
        bootCountNow == lock.bootCount;
    remaining = sameBoot
        ? lock.duration - (elapsedNow - lock.elapsedAtLock!)
        : lock.duration - elapsedNow;
  } else if (now.isBefore(lock.lockedAtWall)) {
    remaining = lock.duration;
  } else {
    remaining = lock.duration - now.difference(lock.lockedAtWall);
  }
  if (remaining.isNegative) return Duration.zero;
  return remaining > lock.duration ? lock.duration : remaining;
}
