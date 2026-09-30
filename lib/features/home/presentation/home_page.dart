import 'package:flutter/material.dart';

import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/feature_card.dart';
import '../../../core/widgets/status_banner.dart';
import '../../app_lock/presentation/app_lock_controller.dart';
import '../../app_lock/presentation/app_lock_page.dart';
import '../../app_lock/presentation/app_lock_setup_page.dart';
import 'device_management_page.dart';

/// S01 — Trang chủ: lối vào "Quản lý thiết bị của con" (có cổng xác thực),
/// thẻ Ứng dụng bị chặn, cảnh báo đỏ khi khóa ứng dụng bị vô hiệu hóa.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _openParentArea(
    BuildContext context,
    String action,
    Widget page,
  ) async {
    final navigator = Navigator.of(context);
    if (!await ParentGate.parentArea(context, action)) return;
    await navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appLock = AppLockScope.maybeOf(context);
    final lockedCount = appLock?.lockedCount ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('SafeFamily')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          if (appLock?.disabled ?? false) ...[
            StatusBanner(
              type: StatusType.error,
              title: 'Khóa ứng dụng đang bị vô hiệu hóa',
              message:
                  'Quyền cần thiết đã bị tắt nên con mở được app bị chặn. '
                  'Đã ghi vào nhật ký.',
              actions: [
                FilledButton(
                  onPressed: () => _openParentArea(
                    context,
                    'Thiết lập khóa ứng dụng',
                    const AppLockSetupPage(),
                  ),
                  child: const Text('Bật lại'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
          ],
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
            onTap: () => _openParentArea(
              context,
              'Quản lý thiết bị của con',
              const DeviceManagementPage(),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          FeatureCard(
            icon: Icons.block_rounded,
            title: 'Ứng dụng bị chặn',
            subtitle: lockedCount == 0
                ? 'Chưa chặn ứng dụng nào'
                : 'Đang chặn $lockedCount ứng dụng — mở tạm cho con ở đây',
            onTap: () =>
                _openParentArea(context, 'Khóa ứng dụng', const AppLockPage()),
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
        ],
      ),
    );
  }
}
