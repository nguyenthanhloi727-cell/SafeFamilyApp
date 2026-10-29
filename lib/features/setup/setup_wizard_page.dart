import 'package:flutter/material.dart';

import '../../core/permissions/permission_registry.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_snack_bar.dart';
import '../../core/widgets/status_banner.dart';

/// Vì sao SafeFamily cần từng quyền (hiện ở mỗi bước của wizard).
const permissionReasons = <AppPermission, String>{
  AppPermission.accessibility:
      'Để chặn ứng dụng khi con mở. Vào Cài đặt → bật dịch vụ SafeFamily.',
  AppPermission.settingsGuard:
      'Để con không tự tắt các quyền của SafeFamily trong Cài đặt máy.',
  AppPermission.usageAccess:
      'Để biết con dùng máy bao lâu, áp giới hạn thời gian và làm báo cáo.',
  AppPermission.notifications: 'Để báo khi con cài app mới hoặc xin thêm giờ.',
  AppPermission.exactAlarm: 'Để báo thức kêu đúng giờ.',
  AppPermission.battery:
      'Để máy không tự tắt SafeFamily khi chạy nền, tránh mất chặn.',
  AppPermission.deviceAdmin:
      'Để con không gỡ được SafeFamily. Gỡ app phải đi qua phụ huynh.',
  AppPermission.microphone: 'Để đặt báo thức bằng giọng nói.',
};

/// Các bước của wizard: bước hướng dẫn "cài đặt bị hạn chế" (nếu còn quyền
/// thiếu) rồi tới từng quyền chưa cấp. Bước null = hướng dẫn.
List<AppPermission?> wizardSteps(PermissionRegistry registry) {
  final missing = [for (final e in registry.missing) e.permission];
  if (missing.isEmpty) return const [];
  return [null, ...missing];
}

/// S15 — Setup Wizard: mỗi bước một quyền, giải thích lý do, mở Cài đặt, quay
/// lại tự kiểm tra rồi sang bước kế. Mỗi bước có "Để sau". Đi hết hoặc bỏ qua
/// đều gọi [onFinished] (nơi gọi lưu cờ `setup_done` / đóng màn).
class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  PermissionRegistry? _registry;
  List<AppPermission?>? _steps;
  int _index = 0;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = PermissionRegistryScope.of(context);
    if (!identical(registry, _registry)) {
      _registry?.removeListener(_onRegistryChanged);
      _registry = registry..addListener(_onRegistryChanged);
      registry.refresh();
      // Sau khung hình đầu: _finish() có thể đổi cây widget phía trên.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onRegistryChanged();
      });
    }
  }

  @override
  void dispose() {
    _registry?.removeListener(_onRegistryChanged);
    super.dispose();
  }

  void _onRegistryChanged() {
    final registry = _registry!;
    if (!registry.isLoaded || _finished) return;
    if (_steps == null) {
      // Chốt danh sách bước một lần, lúc đã đọc xong trạng thái quyền.
      _steps = wizardSteps(registry);
      if (_steps!.isEmpty) {
        _finish();
        return;
      }
    }
    // Vừa bật quyền ở Cài đặt rồi quay lại → tự sang bước kế.
    final current = _steps![_index];
    if (current != null && registry.isGranted(current)) {
      _next();
      return;
    }
    if (mounted) setState(() {});
  }

  void _next() {
    if (_index + 1 >= _steps!.length) {
      _finish();
    } else if (mounted) {
      setState(() => _index++);
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  Future<void> _open(AppPermission permission) async {
    final opened = await _registry!.openSettings(permission);
    if (!opened && mounted) {
      showAppSnackBar(context, 'Máy không mở được trang cài đặt này.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    if (steps == null || steps.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    final step = steps[_index];
    final isHelp = step == null;
    final title = isHelp ? 'Cho phép cài đặt bị hạn chế' : step.label;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết lập quyền'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: (_index + 1) / steps.length),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Bước ${_index + 1}/${steps.length}',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpace.xl),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpace.md),
              Expanded(
                child: SingleChildScrollView(
                  child: isHelp
                      ? const _RestrictedSettingsHelp()
                      : Text(
                          permissionReasons[step] ?? '',
                          style: theme.textTheme.bodyLarge,
                        ),
                ),
              ),
              FilledButton(
                key: const Key('wizard-open'),
                onPressed: isHelp
                    // Trang "Thông tin ứng dụng" cũng là nơi có menu ⋮.
                    ? () => _open(AppPermission.microphone)
                    : () => _open(step),
                child: Text(isHelp ? 'Mở thông tin ứng dụng' : 'Mở Cài đặt'),
              ),
              const SizedBox(height: AppSpace.sm),
              if (isHelp)
                OutlinedButton(
                  key: const Key('wizard-continue'),
                  onPressed: _next,
                  child: const Text('Đã xong, tiếp tục'),
                ),
              TextButton(
                key: const Key('wizard-skip'),
                onPressed: _next,
                child: const Text('Để sau'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Android 13+ chặn bật Trợ năng / Quản trị thiết bị với app cài ngoài Play Store
/// tới khi người dùng cho phép "cài đặt bị hạn chế".
class _RestrictedSettingsHelp extends StatelessWidget {
  const _RestrictedSettingsHelp();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nếu nút bật Trợ năng bị mờ hoặc báo "Cài đặt bị hạn chế" '
          '(Android 13 trở lên, app cài ngoài Play Store), làm như sau:',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpace.md),
        // TODO(verify): tên menu khác nhau theo hãng (Xiaomi, Samsung, Oppo...).
        Text(
          '1. Bấm "Mở thông tin ứng dụng" bên dưới.\n'
          '2. Bấm dấu ba chấm ⋮ ở góc trên bên phải.\n'
          '3. Chọn "Cho phép cài đặt bị hạn chế".\n'
          '4. Quay lại đây và bấm "Đã xong, tiếp tục".',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpace.md),
        const StatusBanner(
          type: StatusType.info,
          title: 'Không thấy dấu ba chấm?',
          message:
              'Máy của bạn không bị hạn chế, bấm "Đã xong, tiếp tục" hoặc '
              '"Để sau".',
        ),
      ],
    );
  }
}
