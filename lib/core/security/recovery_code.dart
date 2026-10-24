import 'dart:math';

/// Bảng chữ cho mã khôi phục: bỏ O/0, I/1/L, S/5, B/8, Z/2 dễ nhầm khi chép tay.
const recoveryAlphabet = 'ACDEFGHJKMNPQRTUVWXY34679';
const recoveryCodeLength = 10;

/// Sinh mã khôi phục [recoveryCodeLength] ký tự bằng bộ sinh ngẫu nhiên an toàn.
String generateRecoveryCode({Random? random}) {
  final rng = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < recoveryCodeLength; i++)
      recoveryAlphabet.codeUnitAt(rng.nextInt(recoveryAlphabet.length)),
  ]);
}

/// Đưa mã người dùng gõ về dạng chuẩn: bỏ khoảng trắng/gạch ngang, viết hoa.
String normalizeRecoveryCode(String input) =>
    input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// Mã hợp lệ về hình thức (đủ độ dài, đúng bảng chữ).
bool isRecoveryCodeFormatValid(String input) {
  final code = normalizeRecoveryCode(input);
  return code.length == recoveryCodeLength &&
      code.split('').every(recoveryAlphabet.contains);
}

/// Hiện mã theo nhóm 5 ký tự cho dễ chép: `ABCDE-FGHJK`.
String formatRecoveryCode(String code) =>
    '${code.substring(0, 5)}-${code.substring(5)}';
