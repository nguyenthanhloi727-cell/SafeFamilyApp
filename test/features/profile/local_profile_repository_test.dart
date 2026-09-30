import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/features/profile/data/local_profile_repository.dart';

void main() {
  setUp(() {
    // Mỗi test một bộ nhớ trống, không đụng máy thật.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('lần đầu tạo sẵn "Mẹ", "Bố" và KHÔNG có số', () async {
    final contacts = await LocalProfileRepository().loadContacts();

    expect(contacts.map((c) => c.label), ['Mẹ', 'Bố']);
    expect(contacts.every((c) => c.phone.isEmpty), isTrue);
    expect(contacts.map((c) => c.id).toSet(), hasLength(2));
  });

  test('chỉ tạo sẵn một lần: xóa hết rồi mở lại vẫn rỗng', () async {
    final repo = LocalProfileRepository();
    for (final c in await repo.loadContacts()) {
      await repo.deleteContact(c.id);
    }

    expect(await LocalProfileRepository().loadContacts(), isEmpty);
  });

  test('thêm vào cuối danh sách', () async {
    final repo = LocalProfileRepository();
    final added = await repo.addContact(label: ' Ông ', phone: '0901234567');

    final contacts = await repo.loadContacts();
    expect(contacts.map((c) => c.label), ['Mẹ', 'Bố', 'Ông']);
    expect(contacts.last, added);
    expect(added.label, 'Ông', reason: 'tên gọi được cắt khoảng trắng');
    expect(added.order, greaterThan(contacts[1].order));
  });

  test('sửa tên gọi và số', () async {
    final repo = LocalProfileRepository();
    final mom = (await repo.loadContacts()).first;

    await repo.updateContact(mom.copyWith(phone: '0901234567'));
    await repo.updateContact(
      (await repo.loadContacts()).first.copyWith(label: 'Mẹ Hoa'),
    );

    final updated = (await repo.loadContacts()).first;
    expect(updated.id, mom.id);
    expect(updated.label, 'Mẹ Hoa');
    expect(updated.phone, '0901234567');
  });

  test('sửa liên hệ không tồn tại thì báo lỗi', () async {
    final repo = LocalProfileRepository();
    final mom = (await repo.loadContacts()).first;
    await repo.deleteContact(mom.id);

    expect(() => repo.updateContact(mom), throwsStateError);
  });

  test('xóa đúng liên hệ', () async {
    final repo = LocalProfileRepository();
    final dad = (await repo.loadContacts())[1];

    await repo.deleteContact(dad.id);

    expect((await repo.loadContacts()).map((c) => c.label), ['Mẹ']);
  });

  test('dữ liệu còn nguyên khi mở lại (instance mới)', () async {
    final first = LocalProfileRepository();
    await first.addContact(label: 'Bà', phone: '+84901234567');
    await first.saveParentName('  Nguyễn Văn A ');

    final reopened = LocalProfileRepository();
    expect((await reopened.loadContacts()).map((c) => c.label), [
      'Mẹ',
      'Bố',
      'Bà',
    ]);
    expect((await reopened.loadContacts()).last.phone, '+84901234567');
    expect(await reopened.loadParentName(), 'Nguyễn Văn A');
  });

  test('chưa đặt tên phụ huynh thì trả về null', () async {
    expect(await LocalProfileRepository().loadParentName(), isNull);
  });
}
