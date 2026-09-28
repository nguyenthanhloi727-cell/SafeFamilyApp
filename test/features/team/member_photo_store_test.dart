import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app_nguyenthanhloi/features/team/data/member_photo_store.dart';

void main() {
  late Directory appDir; // giả làm thư mục riêng của app
  late Directory galleryDir; // giả làm thư viện ảnh

  LocalMemberPhotoStore newStore() =>
      LocalMemberPhotoStore(baseDirectory: () async => appDir);

  Future<String> galleryPhoto(String name, List<int> bytes) async {
    final file = File('${galleryDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    appDir = await Directory.systemTemp.createTemp('sf_app_');
    galleryDir = await Directory.systemTemp.createTemp('sf_gallery_');
  });

  tearDown(() async {
    await appDir.delete(recursive: true);
    await galleryDir.delete(recursive: true);
  });

  test('chưa tải ảnh thì không có đường dẫn', () async {
    expect(await newStore().photoPath('hongocphu'), isNull);
  });

  test('ảnh được CHÉP vào thư mục app — xóa ảnh gốc vẫn còn', () async {
    final source = await galleryPhoto('IMG_001.jpg', [1, 2, 3]);

    final saved = await newStore().savePhoto('hongocphu', source);
    await File(source).delete();

    expect(saved, startsWith(appDir.path));
    expect(await File(saved).readAsBytes(), [1, 2, 3]);
  });

  test('tắt app mở lại (store mới) vẫn còn ảnh', () async {
    final saved = await newStore().savePhoto(
      'hongocphu',
      await galleryPhoto('a.jpg', [7]),
    );

    expect(await newStore().photoPath('hongocphu'), saved);
  });

  test('đổi ảnh: dùng ảnh mới và dọn file cũ', () async {
    final store = newStore();
    final first = await store.savePhoto(
      'hongocphu',
      await galleryPhoto('a.jpg', [1]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await store.savePhoto(
      'hongocphu',
      await galleryPhoto('b.jpg', [2]),
    );

    expect(second, isNot(first));
    expect(await store.photoPath('hongocphu'), second);
    expect(await File(first).exists(), isFalse);
    expect(await File(second).readAsBytes(), [2]);
  });

  test('xóa ảnh: mất cả file lẫn đường dẫn', () async {
    final store = newStore();
    final saved = await store.savePhoto(
      'hongocphu',
      await galleryPhoto('a.jpg', [1]),
    );

    await store.deletePhoto('hongocphu');

    expect(await store.photoPath('hongocphu'), isNull);
    expect(await File(saved).exists(), isFalse);
  });

  test('file trong app bị mất thì trả về null', () async {
    final store = newStore();
    final saved = await store.savePhoto(
      'hongocphu',
      await galleryPhoto('a.jpg', [1]),
    );
    await File(saved).delete();

    expect(await store.photoPath('hongocphu'), isNull);
  });

  test('ảnh của mỗi người tách riêng', () async {
    final store = newStore();
    await store.savePhoto('hongocphu', await galleryPhoto('a.jpg', [1]));

    expect(await store.photoPath('phuongbaokhoi'), isNull);
  });
}
