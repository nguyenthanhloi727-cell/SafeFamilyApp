import 'package:flutter/material.dart';

import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/feature_card.dart';
import 'device_management_page.dart';

/// S01 — Trang chủ: lối vào "Quản lý thiết bị của con" (có cổng xác thực)
/// + các thẻ giữ chỗ cho tính năng quản lý con.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _openDeviceManagement(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (!await ParentGate.parentArea(context, 'Quản lý thiết bị của con')) {
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => const DeviceManagementPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('SafeFamily')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          Text('Xin chào!', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Bảng điều khiển quản lý điện thoại của con',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          FeatureCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Quản lý thiết bị của con',
            subtitle: 'Chỉ phụ huynh — cần vân tay/khuôn mặt hoặc mã PIN',
            onTap: () => _openDeviceManagement(context),
          ),
          const SizedBox(height: AppSpace.md),
          const FeatureCard(
            icon: Icons.child_care_rounded,
            title: 'Thẻ con',
            subtitle: 'Tên, tuổi và thiết bị của con',
            comingSoon: true,
          ),
          const SizedBox(height: AppSpace.md),
          const FeatureCard(
            icon: Icons.hourglass_bottom_rounded,
            title: 'Thời gian dùng máy',
            subtitle: 'Thống kê thời gian con dùng điện thoại mỗi ngày',
            comingSoon: true,
          ),
          const SizedBox(height: AppSpace.md),
          const FeatureCard(
            icon: Icons.block_rounded,
            title: 'Ứng dụng bị chặn',
            subtitle: 'Danh sách ứng dụng con không được mở',
            comingSoon: true,
          ),
        ],
      ),
    );
  }
}
