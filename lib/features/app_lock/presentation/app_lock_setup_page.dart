import 'package:flutter/material.dart';

import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/status_banner.dart';
import '../data/app_lock_platform.dart';
import 'app_lock_controller.dart';

/// Thiết lập khóa ứng dụng: từng quyền cần bật, trạng thái, nút mở đúng
/// trang Cài đặt. Quay lại app là trạng thái tự cập nhật.
class AppLockSetupPage extends StatelessWidget {
  const AppLockSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppLockScope.maybeOf(context);
    final permissions = controller?.permissions;
    final theme = Theme.of(context);

    Future<void> open(AppLockSetting setting) async {
      final opened = await controller?.openSetting(setting) ?? false;
      if (!opened && context.mounted) {
        showAppSnackBar(context, 'Máy không mở được trang Cài đặt này.');
      }
    }

    return ParentAreaGuard(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Thiết lập khóa ứng dụng'),
          actions: [
            IconButton(
              tooltip: 'Kiểm tra lại',
              onPressed: controller?.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (permissions == null)
              const StatusBanner(
                type: StatusType.info,
                title: 'Đang kiểm tra quyền…',
              )
            else if (permissions.ready)
              const StatusBanner(
                type: StatusType.success,
                title: 'Đã bật đủ quyền bắt buộc',
                message: 'Có thể chặn ứng dụng.',
              )
            else
              const StatusBanner(
                type: StatusType.error,
                title: 'Chưa bật đủ quyền',
                message:
                    'Bấm từng nút bên dưới, bật quyền trong Cài đặt rồi bấm '
                    'quay lại SafeFamily.',
              ),
            const SizedBox(height: AppSpace.lg),
            _PermissionCard(
              step: 1,
              title: 'Trợ năng (bắt buộc)',
              description:
                  'Để SafeFamily biết khi con mở app bị chặn. Trong Cài đặt '
                  '→ Trợ năng, tìm "SafeFamily - Khóa ứng dụng" (có máy để '
                  'trong mục "Ứng dụng đã tải xuống") → Bật.',
              note:
                  'Công tắc bị mờ, báo "Cài đặt bị hạn chế" (Android 13 trở '
                  'lên, cài từ file APK): mở Thông tin ứng dụng → nút ⋮ → '
                  '"Cho phép cài đặt bị hạn chế", rồi bật lại.\n'
                  'Trong Cài đặt đã bật mà ở đây vẫn "Chưa bật" (dịch vụ bị '
                  'dừng, thường do vuốt tắt SafeFamily): tắt đi rồi bật lại.',
              granted: permissions?.accessibility,
              onOpen: () => open(AppLockSetting.accessibility),
            ),
            _PermissionCard(
              step: 2,
              title: 'Báo thức & lời nhắc (bắt buộc)',
              description:
                  'Để app mẹ mở tạm tự chặn lại đúng giờ, kể cả khi đã tắt '
                  'SafeFamily.',
              granted: permissions?.exactAlarm,
              onOpen: () => open(AppLockSetting.exactAlarm),
            ),
            _PermissionCard(
              step: 3,
              title: 'Tắt tối ưu pin (nên bật)',
              description:
                  'Để máy không tắt SafeFamily khi chạy nền. Chọn "Cho phép" '
                  'hoặc "Không hạn chế".',
              granted: permissions?.batteryUnrestricted,
              onOpen: () => open(AppLockSetting.battery),
            ),
            const SizedBox(height: AppSpace.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ghi chú theo hãng máy',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    const _VendorNote(
                      vendor: 'Xiaomi / Redmi / POCO',
                      steps:
                          'Thông tin ứng dụng → bật "Tự khởi động"; Tiết kiệm '
                          'pin → "Không giới hạn".',
                    ),
                    const _VendorNote(
                      vendor: 'Oppo / Realme',
                      steps:
                          'Thông tin ứng dụng → bật "Cho phép tự khởi chạy"; '
                          'Mức sử dụng pin → cho phép hoạt động nền.',
                    ),
                    const _VendorNote(
                      vendor: 'Vivo',
                      steps:
                          'i Manager / Cài đặt → bật "Tự khởi động"; Pin → '
                          '"Cho phép mức tiêu thụ pin cao ở chế độ nền".',
                    ),
                    const _VendorNote(
                      vendor: 'Samsung',
                      steps:
                          'Thông tin ứng dụng → Pin → "Không hạn chế"; bỏ '
                          'SafeFamily khỏi danh sách "Ứng dụng ngủ".',
                    ),
                    const SizedBox(height: AppSpace.sm),
                    OutlinedButton.icon(
                      onPressed: () => open(AppLockSetting.appDetails),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Mở Thông tin ứng dụng'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.step,
    required this.title,
    required this.description,
    required this.granted,
    required this.onOpen,
    this.note,
  });

  final int step;
  final String title;
  final String description;
  final String? note;

  /// `null` = chưa kiểm tra xong.
  final bool? granted;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = theme.extension<AppColors>()!;
    final ok = granted ?? false;
    final statusColor = ok ? app.success : theme.colorScheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$step. $title',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (granted != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: statusColor,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Text(
                        ok ? 'Đã bật' : 'Chưa bật',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(description, style: theme.textTheme.bodyMedium),
            if (note != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (!ok) ...[
              const SizedBox(height: AppSpace.sm),
              FilledButton.tonal(
                onPressed: onOpen,
                child: const Text('Mở Cài đặt'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VendorNote extends StatelessWidget {
  const _VendorNote({required this.vendor, required this.steps});

  final String vendor;
  final String steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$vendor: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: steps),
          ],
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}
