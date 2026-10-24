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

  test('chỉ một liên hệ khẩn cấp, và được đồng bộ sang native', () async {
    final repo = LocalProfileRepository();
    await repo.addContact(label: 'Ông', phone: '0901234567');
    List<FamilyContact> synced = const [];
    final controller = ProfileController(
      repo,
      onContactsChanged: (c) async => synced = c,
    );
    await controller.load();
    final a = controller.contacts.firstWhere((c) => c.label == 'Mẹ');
    final b = controller.contacts.firstWhere((c) => c.label == 'Ông');

    await controller.setEmergency(a.id);
    await controller.setEmergency(b.id);

    expect(controller.contacts.where((c) => c.emergency).map((c) => c.label), [
      'Ông',
    ]);
    expect(synced.where((c) => c.emergency).single.label, 'Ông');
    await controller.setEmergency(null);
    expect(controller.contacts.any((c) => c.emergency), isFalse);
  });
}
