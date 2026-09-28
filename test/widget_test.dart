import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  await tester.pumpAndSettle();
}

void main() {
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
    await tester.pumpAndSettle();
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
