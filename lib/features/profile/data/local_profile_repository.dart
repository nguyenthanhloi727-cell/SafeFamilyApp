import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'family_contact.dart';
import 'profile_repository.dart';

/// Lưu trên máy bằng shared_preferences (danh bạ dạng JSON).
class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const parentNameKey = 'profile.parent_name';
  static const contactsKey = 'profile.family_contacts';

  /// Liên hệ tạo sẵn lần đầu — KHÔNG có số, tránh bấm nhầm gọi trúng người thật.
  static const seedLabels = ['Mẹ', 'Bố'];

  final SharedPreferencesAsync _prefs;
  int _idCounter = 0;

  @override
  Future<String?> loadParentName() => _prefs.getString(parentNameKey);

  @override
  Future<void> saveParentName(String name) =>
      _prefs.setString(parentNameKey, name.trim());

  @override
  Future<List<FamilyContact>> loadContacts() async {
    final raw = await _prefs.getString(contactsKey);
    if (raw == null) {
      final seeded = [
        for (final (i, label) in seedLabels.indexed)
          FamilyContact(id: _newId(), label: label, phone: '', order: i),
      ];
      await _write(seeded);
      return seeded;
    }
    final list = [
      for (final item in jsonDecode(raw) as List<Object?>)
        FamilyContact.fromJson(item! as Map<String, Object?>),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  @override
  Future<FamilyContact> addContact({
    required String label,
    String phone = '',
  }) async {
    final contacts = await loadContacts();
    final nextOrder = contacts.isEmpty
        ? 0
        : contacts.map((c) => c.order).reduce((a, b) => a > b ? a : b) + 1;
    final contact = FamilyContact(
      id: _newId(),
      label: label.trim(),
      phone: phone,
      order: nextOrder,
    );
    await _write([...contacts, contact]);
    return contact;
  }

  @override
  Future<void> updateContact(FamilyContact contact) async {
    final contacts = await loadContacts();
    final index = contacts.indexWhere((c) => c.id == contact.id);
    if (index < 0) throw StateError('Không tìm thấy liên hệ ${contact.id}');
    contacts[index] = contact;
    await _write(contacts);
  }

  @override
  Future<void> deleteContact(String id) async {
    final contacts = await loadContacts();
    await _write(contacts.where((c) => c.id != id).toList());
  }

  Future<void> _write(List<FamilyContact> contacts) => _prefs.setString(
    contactsKey,
    jsonEncode([for (final c in contacts) c.toJson()]),
  );

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';
}
