import 'package:flutter/material.dart';

import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/feature_card.dart';
import '../../../core/widgets/status_banner.dart';
import '../../app_lock/presentation/app_lock_page.dart';
import '../../app_lock/presentation/app_lock_setup_page.dart';

/// S20 — Quản lý thiết bị của con (sau cổng xác thực phụ huynh).
class DeviceManagementPage extends StatelessWidget {
  const DeviceManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => page));

    return ParentAreaGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Quản lý thiết bị của con')),
        body: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            const StatusBanner(
              type: StatusType.info,
              title: 'Khu vực này chỉ phụ huynh vào được.',
            ),
            const SizedBox(height: AppSpace.lg),
            FeatureCard(
              icon: Icons.block_rounded,
              title: 'Chặn ứng dụng',
              subtitle: 'Chọn app con không được mở, mở tạm khi cần',
              onTap: () => open(const AppLockPage()),
            ),
            const SizedBox(height: AppSpace.md),
            FeatureCard(
              icon: Icons.tune_rounded,
              title: 'Thiết lập khóa ứng dụng',
              subtitle: 'Bật quyền Trợ năng, báo thức, tối ưu pin',
              onTap: () => open(const AppLockSetupPage()),
            ),
            const SizedBox(height: AppSpace.md),
            const FeatureCard(
              icon: Icons.hourglass_bottom_rounded,
              title: 'Giới hạn thời gian',
              subtitle: 'Số phút dùng máy mỗi ngày',
              comingSoon: true,
            ),
          ],
        ),
      ),
    );
  }
}
