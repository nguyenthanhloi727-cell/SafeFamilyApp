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
