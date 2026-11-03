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

  test('tên phụ huynh còn nguyên khi mở lại (instance mới), được cắt khoảng trắng', () async {
    await LocalProfileRepository().saveParentName('  Nguyễn Văn A ');

    expect(await LocalProfileRepository().loadParentName(), 'Nguyễn Văn A');
  });

  test('chưa đặt tên phụ huynh thì trả về null', () async {
    expect(await LocalProfileRepository().loadParentName(), isNull);
  });
}
