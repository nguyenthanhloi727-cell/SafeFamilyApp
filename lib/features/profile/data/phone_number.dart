/// Số chữ số tối thiểu / tối đa (không tính dấu `+`).
const phoneMinDigits = 9;
const phoneMaxDigits = 12;

final _separators = RegExp(r'[\s.]');
final _validFormat = RegExp(r'^\+?\d+$');

/// Bỏ khoảng trắng và dấu chấm: "090.123 4567" → "0901234567".
String normalizePhone(String input) => input.replaceAll(_separators, '');

/// Trả về câu báo lỗi (tiếng Việt), hoặc `null` nếu số hợp lệ.
///
/// Hợp lệ: chỉ chữ số, cho phép một dấu `+` ở đầu, dài 9–12 chữ số
/// sau khi bỏ khoảng trắng/dấu chấm.
String? validatePhone(String input) {
  final phone = normalizePhone(input);
  if (phone.isEmpty) return 'Nhập số điện thoại';
  if (!_validFormat.hasMatch(phone)) {
    return 'Chỉ gồm chữ số, được có dấu + ở đầu';
  }
  final digits = phone.startsWith('+') ? phone.length - 1 : phone.length;
  if (digits < phoneMinDigits || digits > phoneMaxDigits) {
    return 'Số điện thoại phải dài $phoneMinDigits–$phoneMaxDigits chữ số';
  }
  return null;
}
