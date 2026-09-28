import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app_nguyenthanhloi/app/app.dart';
import 'package:safe_family_app_nguyenthanhloi/features/alarm/presentation/alarm_page.dart';
import 'package:safe_family_app_nguyenthanhloi/features/home/presentation/home_page.dart';
import 'package:safe_family_app_nguyenthanhloi/features/profile/presentation/profile_page.dart';
import 'package:safe_family_app_nguyenthanhloi/features/team/presentation/team_page.dart';
import 'package:safe_family_app_nguyenthanhloi/features/translate/presentation/translate_page.dart';

const _tabs = <(String, Type)>[
  ('Trang chủ', HomePage),
  ('Dịch', TranslatePage),
  ('Báo thức', AlarmPage),
  ('Nhóm', TeamPage),
  ('Cá nhân', ProfilePage),
];

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text(label),
    ),
  );
  // Không dùng pumpAndSettle: IndexedStack dựng cả 5 tab ngay từ đầu, tab Nhóm
  // đọc assets thật (IO thật) nên vòng loading chưa dừng trong thời gian giả
  // của test. Chỉ cần xong hiệu ứng chuyển tab.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    // Tab Cá nhân đọc dữ liệu đã lưu — dùng bộ nhớ giả, không đụng máy thật.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('BottomNavigationBar chuyển đủ 5 tab', (tester) async {
    await tester.pumpWidget(const SafeFamilyApp());

    final barFinder = find.byType(BottomNavigationBar);
    expect(barFinder, findsOneWidget);
    final bar = tester.widget<BottomNavigationBar>(barFinder);
    expect(bar.type, BottomNavigationBarType.fixed);
    expect(bar.items.map((item) => item.label), _tabs.map((tab) => tab.$1));

    // Đi 1 → 5 rồi quay lại tab đầu.
    for (final (index, (label, page)) in [..._tabs, _tabs.first].indexed) {
      await _tapTab(tester, label);
      final expected = index % _tabs.length;
      expect(
        tester.widget<BottomNavigationBar>(barFinder).currentIndex,
        expected,
        reason: 'Bấm "$label" phải chọn tab $expected',
      );
      expect(find.byType(page), findsOneWidget, reason: '"$label" phải hiện');
      for (final (_, other) in _tabs.where((tab) => tab.$2 != page)) {
        expect(find.byType(other), findsNothing, reason: 'Chỉ hiện 1 tab');
      }
    }
  });

  testWidgets('Giữ trạng thái tab khi chuyển qua lại (IndexedStack)', (
    tester,
  ) async {
    await tester.pumpWidget(const SafeFamilyApp());

    await _tapTab(tester, 'Dịch');
    Finder source() => find.descendant(
      of: find.byKey(const Key('source-lang')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(source()).data, 'Tiếng Việt');

    await tester.tap(find.byTooltip('Đổi chiều'));
    await tester.pump();
    expect(tester.widget<Text>(source()).data, 'English');

    await _tapTab(tester, 'Nhóm');
    await _tapTab(tester, 'Dịch');
    expect(
      tester.widget<Text>(source()).data,
      'English',
      reason: 'Quay lại tab Dịch phải giữ cặp ngôn ngữ đã đổi',
    );
  });
}
