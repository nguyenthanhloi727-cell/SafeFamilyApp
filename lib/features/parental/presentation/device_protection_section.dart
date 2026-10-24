import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';

import '../../../core/security/device_guard.dart';
import '../../../core/security/parent_guard.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';

/// Hai lớp chống bypass phía Android: dịch vụ chặn màn Cài đặt và quản trị
/// thiết bị. Trạng thái tự cập nhật khi quay lại app từ Cài đặt.
class DeviceProtectionSection extends StatefulWidget {
  const DeviceProtectionSection({super.key, required this.guard});

  final ParentGuard guard;

  @override
  State<DeviceProtectionSection> createState() =>
      _DeviceProtectionSectionState();
}

class _DeviceProtectionSectionState extends State<DeviceProtectionSection>
    with WidgetsBindingObserver {
  DeviceGuardStatus? _status;

  DeviceGuardPlatform get _device => widget.guard.device;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _device.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _openAccessibility() async {
    await _device.allowSettings(settingsAllowSeconds);
    try {
      await const AndroidIntent(
        action: 'android.settings.ACCESSIBILITY_SETTINGS',
      ).launch();
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Máy không mở được trang Trợ năng.');
      }
    }
  }

  Future<void> _requestAdmin() async {
    await _device.allowSettings(settingsAllowSeconds);
    await _device.requestDeviceAdmin();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;

    Widget state(bool? on) => Text(
      on == null
          ? '…'
          : on
          ? 'Đã bật'
          : 'Chưa bật',
      style: theme.textTheme.labelLarge?.copyWith(
        color: on == true ? theme.colorScheme.primary : theme.colorScheme.error,
      ),
    );

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.settings_accessibility_rounded),
          title: const Text('Bảo vệ màn Cài đặt'),
          subtitle: const Text(
            'Con mở màn xóa dữ liệu, Trợ năng hay gỡ SafeFamily sẽ bị hỏi PIN.',
          ),
          trailing: state(status?.settingsGuard),
          onTap: status?.settingsGuard == true ? null : _openAccessibility,
        ),
        ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Quản trị thiết bị (chống gỡ app)'),
          subtitle: const Text(
            'Đang bật thì phải tắt quyền này mới gỡ được SafeFamily.',
          ),
          trailing: state(status?.deviceAdmin),
          onTap: status?.deviceAdmin == true ? null : _requestAdmin,
        ),
        const SizedBox(height: AppSpace.xs),
      ],
    );
  }
}
