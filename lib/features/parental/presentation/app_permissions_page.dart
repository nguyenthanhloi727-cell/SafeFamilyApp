import 'package:flutter/material.dart';

import '../../../core/permissions/permission_registry.dart';
import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/status_banner.dart';

/// Màn "Quyền ứng dụng": mọi quyền SafeFamily đang dùng.
/// Quyền đã cấp → nút Tắt (xác thực phụ huynh rồi mở đúng trang Cài đặt;
/// Quản trị thiết bị thì tắt thẳng). Chưa cấp → nút Bật.
class AppPermissionsPage extends StatelessWidget {
  const AppPermissionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = PermissionRegistryScope.of(context);
    return ParentAreaGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Quyền ứng dụng')),
        body: ListenableBuilder(
          listenable: registry,
          builder: (context, _) {
            if (!registry.isLoaded) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpace.lg),
              children: [
                const StatusBanner(
                  type: StatusType.info,
                  title: 'Tắt quyền cần xác thực phụ huynh.',
                  message:
                      'Bấm Tắt sẽ mở trang Cài đặt của máy. Tắt quyền xong '
                      'quay lại đây, trạng thái tự cập nhật.',
                ),
                const SizedBox(height: AppSpace.md),
                for (final entry in registry.entries)
                  _PermissionTile(registry: registry, entry: entry),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({required this.registry, required this.entry});

  final PermissionRegistry registry;
  final PermissionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final granted = entry.granted;
    return Card(
      child: ListTile(
        key: Key('permission-${entry.id}'),
        leading: Icon(
          granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: granted ? Colors.green : theme.colorScheme.error,
        ),
        title: Text(entry.name),
        subtitle: Text(granted ? 'Đang bật' : 'Chưa bật'),
        trailing: granted
            ? OutlinedButton(
                key: Key('permission-off-${entry.id}'),
                onPressed: () => _turnOff(context),
                child: const Text('Tắt'),
              )
            : FilledButton(
                key: Key('permission-on-${entry.id}'),
                onPressed: () => _turnOn(context),
                child: const Text('Bật'),
              ),
      ),
    );
  }

  Future<void> _turnOn(BuildContext context) async {
    final opened = await registry.openSettings(entry.permission);
    if (!opened && context.mounted) {
      showAppSnackBar(context, 'Máy không mở được trang cài đặt này.');
    }
  }

  Future<void> _turnOff(BuildContext context) async {
    final action = 'Tắt quyền ${entry.name}';
    if (!await ParentGate.always(context, action)) return;
    final isAdmin = entry.permission == AppPermission.deviceAdmin;
    final ok = isAdmin
        ? await registry.removeDeviceAdmin()
        : await registry.openSettings(entry.permission);
    if (!ok && context.mounted) {
      showAppSnackBar(
        context,
        isAdmin
            ? 'Chưa tắt được Quản trị thiết bị.'
            : 'Máy không mở được trang cài đặt này.',
      );
    }
  }
}
