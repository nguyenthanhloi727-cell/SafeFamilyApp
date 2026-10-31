import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/features/profile/data/family_contact.dart';
import 'package:safe_family_app/features/profile/data/local_profile_repository.dart';
import 'package:safe_family_app/features/profile/presentation/profile_controller.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('tối đa 3 liên hệ khẩn cấp, bật/tắt và đồng bộ sang native', () async {
    final repo = LocalProfileRepository();
    await repo.addContact(label: 'Ông', phone: '0901234567');
    await repo.addContact(label: 'Bà', phone: '0901234568');
    await repo.addContact(label: 'Dì', phone: '0901234569');
    List<FamilyContact> synced = const [];
    final controller = ProfileController(
      repo,
      onContactsChanged: (c) async => synced = c,
    );
    await controller.load();
    FamilyContact byLabel(String l) =>
        controller.contacts.firstWhere((c) => c.label == l);

    // Liên hệ mặc định "Mẹ" chưa có số: không đặt SOS được.
    expect(await controller.toggleEmergency(byLabel('Mẹ').id), isFalse);
    await controller.updateContact(byLabel('Mẹ').copyWith(phone: '0901234560'));
    expect(await controller.toggleEmergency(byLabel('Mẹ').id), isTrue);
    expect(await controller.toggleEmergency(byLabel('Ông').id), isTrue);
    expect(await controller.toggleEmergency(byLabel('Bà').id), isTrue);
    // Đủ 3: người thứ 4 bị từ chối, không đổi gì.
    expect(await controller.toggleEmergency(byLabel('Dì').id), isFalse);
    expect(
      controller.contacts.where((c) => c.emergency).map((c) => c.label),
      unorderedEquals(['Mẹ', 'Ông', 'Bà']),
    );
    expect(synced.where((c) => c.emergency), hasLength(3));

    // Bỏ một người thì thêm được người khác.
    expect(await controller.toggleEmergency(byLabel('Ông').id), isTrue);
    expect(byLabel('Ông').emergency, isFalse);
    expect(await controller.toggleEmergency(byLabel('Dì').id), isTrue);
  });
}
