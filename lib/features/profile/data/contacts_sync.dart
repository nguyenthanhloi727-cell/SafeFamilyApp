import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'family_contact.dart';

/// Chép danh bạ sang Android để màn chặn dùng cho nút SOS khi Flutter không chạy.
/// Chỉ gửi người có số; lỗi kênh (test, máy không phải Android) bị bỏ qua.
Future<void> syncContactsToNative(List<FamilyContact> contacts) async {
  try {
    await const MethodChannel('safefamily/guard')
        .invokeMethod<void>('setContacts', [
          for (final c in contacts.where((c) => c.hasPhone))
            {'label': c.label, 'phone': c.phone, 'emergency': c.emergency},
        ]);
  } catch (error) {
    debugPrint('Không chép được danh bạ sang Android: $error');
  }
}
