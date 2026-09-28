import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/feature_card.dart';
import '../../../core/widgets/step_notice.dart';

/// S01 — Trang chủ: bảng điều khiển giữ chỗ cho tính năng quản lý con.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

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
          const StepNotice(
            'Quản lý con nằm ngoài 8 bước của đồ án — hiện chỉ giữ chỗ.',
          ),
          const SizedBox(height: AppSpace.lg),
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
