import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/feature_registry.dart';
import '../../../core/permissions/permission_registry.dart';
import '../../../core/security/device_guard.dart';
import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/status_banner.dart';
import '../../app_lock/presentation/app_lock_controller.dart';
import '../../time_limit/data/time_limit_platform.dart';

/// Số giây còn lại tới [endsAt], không âm. Luôn tính từ đồng hồ, không đếm dồn.
Duration remainingUntil(DateTime endsAt, DateTime now) {
  final left = endsAt.difference(now);
  return left.isNegative ? Duration.zero : left;
}

/// `giờ:phút:giây`, ví dụ `01:05:09`.
String formatCountdown(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Màn "Đang cản trở": quyền đang bật + tính năng đang chạy, mỗi dòng có nút
/// dẫn tới chỗ tắt. Mở từ trang chủ (đã qua cổng phụ huynh).
class ActiveRestrictionsPage extends StatefulWidget {
  const ActiveRestrictionsPage({super.key, this.registry, this.clock});

  /// Mặc định dựng từ nền tảng thật + khóa ứng dụng/khóa phụ huynh trên cây.
  final FeatureRegistry? registry;
  final DateTime Function()? clock;

  @override
  State<ActiveRestrictionsPage> createState() => _ActiveRestrictionsPageState();
}

class _ActiveRestrictionsPageState extends State<ActiveRestrictionsPage> {
  FeatureRegistry? _registry;
  List<RestrictionFeature>? _features;
  Timer? _ticker;
  bool _reloading = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registry ??=
        widget.registry ??
        FeatureRegistry(
          timeLimit: const MethodChannelTimeLimit(),
          deviceGuard: const MethodChannelDeviceGuard(),
          appLock: AppLockScope.maybeOf(context),
          parentGuard: ParentGuardScope.read(context),
        );
    if (_features == null && _ticker == null) {
      _reload();
      // Chỉ để vẽ lại; số còn lại tính từ endsAt - now.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_reloading) return;
    _reloading = true;
    try {
      final list = await _registry!.activeFeatures();
      if (!mounted) return;
      setState(() {
        // Quyền (có settingsIntent) đã nằm ở nhóm "Quyền đang bật".
        _features = [
          for (final f in list)
            if (f.settingsIntent == null) f,
        ];
      });
    } finally {
      _reloading = false;
    }
  }

  void _tick() {
    if (!mounted) return;
    final now = _now();
    final expired = _features?.any((f) {
      final end = f.endsAt;
      return end != null && !end.isAfter(now);
    });
    if (expired ?? false) {
      _reload(); // Tính năng tự hết → dòng biến mất.
    } else {
      setState(() {});
    }
  }

  Future<void> _disable(RestrictionFeature feature) async {
    final disable = feature.disable;
    if (disable == null) return;
    final done = await disable(ParentGate.promptFor(context));
    if (done) await _reload();
  }

  Future<void> _turnOffPermission(
    PermissionRegistry registry,
    PermissionEntry entry,
  ) async {
    if (!await ParentGate.always(context, 'Tắt quyền ${entry.name}')) return;
    final isAdmin = entry.permission == AppPermission.deviceAdmin;
    final ok = isAdmin
        ? await registry.removeDeviceAdmin()
        : await registry.openSettings(entry.permission);
    if (!ok && mounted) {
      showAppSnackBar(
        context,
        isAdmin
            ? 'Chưa tắt được Quản trị thiết bị.'
            : 'Máy không mở được trang cài đặt này.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = PermissionRegistryScope.maybeOf(context);
    return ParentAreaGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Đang cản trở')),
        body: permissions == null
            ? _body(context, null)
            : ListenableBuilder(
                listenable: permissions,
                builder: (context, _) => _body(context, permissions),
              ),
      ),
    );
  }

  Widget _body(BuildContext context, PermissionRegistry? permissions) {
    final features = _features;
    if (features == null || (permissions != null && !permissions.isLoaded)) {
      return const Center(child: CircularProgressIndicator());
    }
    final granted = permissions?.granted ?? const <PermissionEntry>[];
    if (features.isEmpty && granted.isEmpty) {
      return const Center(
        key: Key('restrictions-empty'),
        child: Text('Máy đang dùng bình thường'),
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        const StatusBanner(
          type: StatusType.info,
          title: 'Tắt gì cũng cần xác thực phụ huynh.',
        ),
        const SizedBox(height: AppSpace.md),
        if (granted.isNotEmpty) ...[
          Text('Quyền đang bật', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpace.sm),
          for (final entry in granted)
            Card(
              child: ListTile(
                key: Key('restriction-permission-${entry.id}'),
                title: Text(entry.name),
                trailing: OutlinedButton(
                  key: Key('restriction-permission-off-${entry.id}'),
                  onPressed: () => _turnOffPermission(permissions!, entry),
                  child: const Text('Tắt'),
                ),
              ),
            ),
          const SizedBox(height: AppSpace.md),
        ],
        if (features.isNotEmpty) ...[
          Text('Tính năng đang chạy', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpace.sm),
          for (final feature in features) _featureTile(feature),
        ],
      ],
    );
  }

  Widget _featureTile(RestrictionFeature feature) {
    final end = feature.endsAt;
    return Card(
      child: ListTile(
        key: Key('restriction-feature-${feature.id}'),
        title: Text(feature.name),
        subtitle: end == null
            ? const Text('Chạy đến khi phụ huynh tắt')
            : Text(
                'Còn ${formatCountdown(remainingUntil(end, _now()))}',
                key: Key('restriction-countdown-${feature.id}'),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
        trailing: feature.disable == null
            ? null
            : OutlinedButton(
                key: Key('restriction-off-${feature.id}'),
                onPressed: () => _disable(feature),
                child: const Text('Tắt'),
              ),
      ),
    );
  }
}
