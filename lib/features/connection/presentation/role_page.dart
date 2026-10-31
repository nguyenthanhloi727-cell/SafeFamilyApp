import 'package:flutter/material.dart';

import '../../../core/network/connection_session.dart';
import '../../../core/theme/app_tokens.dart';
import 'child_pair_page.dart';
import 'parent_login_page.dart';

/// Lần đầu cài: máy này dùng một mình, là máy mẹ, hay là máy con.
/// Chọn "Dùng một máy" thì app chạy như trước, không cần mạng.
class RolePage extends StatelessWidget {
  const RolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = ConnectionScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Máy này dùng để làm gì?')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          _RoleCard(
            key: const Key('role-local'),
            icon: Icons.phone_android_rounded,
            title: 'Dùng một máy',
            subtitle:
                'Quản lý ngay trên máy này, không cần tài khoản hay mạng.',
            onTap: () => session.setMode(ConnectionMode.local),
          ),
          _RoleCard(
            key: const Key('role-parent'),
            icon: Icons.supervisor_account_rounded,
            title: 'Máy mẹ',
            subtitle: 'Đăng nhập, tạo mã ghép đôi và đặt luật cho máy của con.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ParentLoginPage()),
            ),
          ),
          _RoleCard(
            key: const Key('role-child'),
            icon: Icons.child_care_rounded,
            title: 'Máy con',
            subtitle: 'Nhập mã 6 số do mẹ tạo để kết nối với máy của mẹ.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChildPairPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpace.lg),
        leading: Icon(icon, size: 32),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
