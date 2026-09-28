import 'package:flutter/material.dart';

import '../features/alarm/presentation/alarm_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/team/presentation/team_page.dart';
import '../features/translate/presentation/translate_page.dart';

class _AppTab {
  const _AppTab(this.label, this.icon, this.activeIcon, this.page);

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;
}

/// Khung điều hướng chính: 5 tab bằng [BottomNavigationBar] (mục 1 của thầy).
///
/// [IndexedStack] giữ nguyên trạng thái từng tab khi chuyển qua lại.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _tabs = [
    _AppTab('Trang chủ', Icons.home_outlined, Icons.home, HomePage()),
    _AppTab('Dịch', Icons.translate, Icons.translate, TranslatePage()),
    _AppTab('Báo thức', Icons.alarm_outlined, Icons.alarm, AlarmPage()),
    _AppTab('Nhóm', Icons.groups_outlined, Icons.groups, TeamPage()),
    _AppTab('Cá nhân', Icons.person_outline, Icons.person, ProfilePage()),
  ];

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [for (final tab in _tabs) tab.page],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          for (final tab in _tabs)
            BottomNavigationBarItem(
              icon: Icon(tab.icon),
              activeIcon: Icon(tab.activeIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
