import 'package:flutter/material.dart';

import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/feature_card.dart';
import '../../../core/widgets/status_banner.dart';

/// S20 — Quản lý thiết bị của con (sau cổng xác thực phụ huynh).
class DeviceManagementPage extends StatelessWidget {
  const DeviceManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentAreaGuard(child: _page());
  }

  Widget _page() {
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý thiết bị của con')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: const [
          StatusBanner(
            type: StatusType.info,
            title: 'Sắp có: chặn app, giới hạn thời gian',
            message: 'Khu vực này chỉ phụ huynh vào được.',
          ),
          SizedBox(height: AppSpace.lg),
          FeatureCard(
            icon: Icons.block_rounded,
            title: 'Chặn ứng dụng',
            subtitle: 'Chọn app con không được mở',
            comingSoon: true,
          ),
          SizedBox(height: AppSpace.md),
          FeatureCard(
            icon: Icons.hourglass_bottom_rounded,
            title: 'Giới hạn thời gian',
            subtitle: 'Số phút dùng máy mỗi ngày',
            comingSoon: true,
          ),
        ],
      ),
    );
  }
}
