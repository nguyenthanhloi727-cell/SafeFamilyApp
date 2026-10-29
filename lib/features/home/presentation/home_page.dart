import 'package:flutter/material.dart';

import '../../../core/permissions/permission_registry.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/settings/setup_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/feature_card.dart';
import '../../../core/widgets/status_banner.dart';
import '../../app_lock/presentation/app_lock_controller.dart';
import '../../app_lock/presentation/app_lock_page.dart';
import '../../app_lock/presentation/block_schedules.dart';
import '../../app_lock/presentation/app_lock_setup_page.dart';
import '../../report/presentation/report_page.dart';
import '../../setup/setup_wizard_page.dart';
import '../../report/presentation/usage_summary_card.dart';
import '../../time_limit/presentation/pause_card.dart';
import 'active_restrictions_page.dart';
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

  /// Mở lại wizard từ banner "Còn thiếu N quyền".
  Future<void> _openWizard(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (!await ParentGate.parentArea(context, 'Thiết lập quyền')) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SetupWizardPage(onFinished: navigator.pop),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registry = PermissionRegistryScope.maybeOf(context);
    final setupDone = SetupSettingsScope.maybeOf(context)?.isDone ?? true;
    final missingCount = registry?.missing.length ?? 0;
    final appLock = AppLockScope.maybeOf(context);
    final lockedCount = appLock?.lockedCount ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('SafeFamily')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          if (setupDone &&
              (registry?.isLoaded ?? false) &&
              missingCount > 0) ...[
            StatusBanner(
              type: StatusType.warning,
              title: 'Còn thiếu $missingCount quyền',
              message: 'Bổ sung để SafeFamily bảo vệ máy đầy đủ.',
              actions: [
                FilledButton(
                  key: const Key('missing-permissions-banner'),
                  onPressed: () => _openWizard(context),
                  child: const Text('Thiết lập'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
          ],
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
            onTap: () => _openParentArea(
              context,
              'Xem ứng dụng bị chặn',
              const AppLockPage(onlyLocked: true, footer: BlockSchedules()),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          FeatureCard(
            icon: Icons.lock_clock_outlined,
            title: 'Đang cản trở',
            subtitle: 'Quyền và tính năng đang chạy, tắt ngay tại đây',
            onTap: () => _openParentArea(
              context,
              'Xem tính năng đang cản trở',
              const ActiveRestrictionsPage(),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          const PauseCard(),
          const SizedBox(height: AppSpace.md),
          const FeatureCard(
            icon: Icons.child_care_rounded,
            title: 'Thẻ con',
            subtitle: 'Tên, tuổi và thiết bị của con',
            comingSoon: true,
          ),
          const SizedBox(height: AppSpace.md),
          UsageSummaryCard(
            onTap: () => _openParentArea(
              context,
              'Báo cáo thời gian dùng',
              const ReportPage(),
            ),
          ),
        ],
      ),
    );
  }
}
