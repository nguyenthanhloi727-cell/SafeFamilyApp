import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/status_banner.dart';

/// Phía mẹ: app mới cài của máy con đọc từ server (API-07). Cho phép / chặn đều qua `ParentGate.always`
/// (huỷ khóa thì không gọi server). Máy con áp quyết định ở lượt đồng bộ kế (tối đa vài phút).
class RemoteNewAppsView extends StatefulWidget {
  const RemoteNewAppsView({super.key, required this.device});

  final DeviceInfo device;

  @override
  State<RemoteNewAppsView> createState() => _RemoteNewAppsViewState();
}

class _RemoteNewAppsViewState extends State<RemoteNewAppsView> {
  List<InstalledAppInfo>? _new;
  List<InstalledAppInfo> _blocked = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final api = ApiScope.of(context);
    try {
      final fresh = await api.getDeviceApps(
        widget.device.id,
        status: AppStatus.isNew,
      );
      final blocked = await api.getDeviceApps(
        widget.device.id,
        status: AppStatus.blocked,
      );
      if (!mounted) return;
      setState(() {
        _new = fresh;
        _blocked = blocked;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(InstalledAppInfo app, {required bool allow}) async {
    if (_busy) return;
    final api = ApiScope.of(context);
    final what = '${allow ? 'Cho phép' : 'Chặn'} app ${app.label}';
    if (!await ParentGate.always(context, what)) return;
    setState(() => _busy = true);
    try {
      await api.setDeviceAppStatus(
        widget.device.id,
        app.packageName,
        allow: allow,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          '${allow ? 'Đã cho phép' : 'Đã chặn'} ${app.label}. '
          'Máy con nhận ở lần đồng bộ kế (tối đa vài phút).',
        );
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  Widget _tile(InstalledAppInfo app, {required bool offerBlock}) {
    final theme = Theme.of(context);
    return Card(
      key: Key('app-${app.packageName}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(offerBlock ? Icons.new_releases_outlined : Icons.block),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.label,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        app.packageName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                if (offerBlock) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: Key('block-${app.packageName}'),
                      onPressed: _busy
                          ? null
                          : () => _decide(app, allow: false),
                      child: const Text('Chặn'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                ],
                Expanded(
                  child: FilledButton(
                    key: Key('allow-${app.packageName}'),
                    onPressed: _busy ? null : () => _decide(app, allow: true),
                    child: const Text('Cho phép'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fresh = _new;
    return Scaffold(
      appBar: AppBar(title: Text('App mới của ${widget.device.name}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (fresh == null && _error == null)
              const LinearProgressIndicator(),
            if (fresh != null && fresh.isEmpty)
              const StatusBanner(
                type: StatusType.success,
                title: 'Không có app nào chờ duyệt',
              ),
            if (fresh != null && fresh.isNotEmpty) ...[
              Text(
                'Đang chờ duyệt (${fresh.length})',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpace.sm),
              for (final app in fresh) _tile(app, offerBlock: true),
            ],
            if (_blocked.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              Text(
                'Đã chặn (${_blocked.length})',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpace.sm),
              for (final app in _blocked) _tile(app, offerBlock: false),
            ],
          ],
        ),
      ),
    );
  }
}
