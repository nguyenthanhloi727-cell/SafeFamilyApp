import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/child_status_text.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';

/// "Cảnh báo của máy con": đổi giờ, cố gỡ app, tắt Trợ năng / Quản trị thiết bị, thiếu quyền, mất kết nối.
/// Chỉ có loại sự kiện và thời điểm, không nội dung, không vị trí.
///
/// Đánh dấu đã đọc KHÔNG qua khóa phụ huynh: nó chỉ đổi cờ đọc, không mở/tắt/duyệt gì và cảnh báo vẫn nằm trong
/// danh sách. Màn này nằm trong khu vực của mẹ (máy mẹ đã đăng nhập).
class DeviceAlertsPage extends StatefulWidget {
  const DeviceAlertsPage({super.key, required this.device});

  final DeviceInfo device;

  @override
  State<DeviceAlertsPage> createState() => _DeviceAlertsPageState();
}

class _DeviceAlertsPageState extends State<DeviceAlertsPage> {
  List<AlertInfo>? _alerts;
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
      final list = await api.getAlerts(widget.device.id);
      if (mounted) {
        setState(() {
          // Mới nhất trước.
          _alerts = list.reversed.toList();
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _markRead(List<AlertInfo> targets) async {
    if (_busy || targets.isEmpty) return;
    final api = ApiScope.of(context);
    setState(() => _busy = true);
    try {
      for (final a in targets) {
        await api.markAlertRead(a.id);
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alerts = _alerts;
    final unread = [
      for (final a in alerts ?? const <AlertInfo>[])
        if (a.isUnread) a,
    ];
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text('Cảnh báo của ${widget.device.name}'),
        actions: [
          if (unread.isNotEmpty)
            TextButton(
              key: const Key('alerts-mark-all'),
              onPressed: _busy ? null : () => _markRead(unread),
              child: const Text('Đã đọc hết'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (alerts == null && _error == null) const LinearProgressIndicator(),
            if (alerts != null && alerts.isEmpty)
              const Text('Chưa có cảnh báo nào.'),
            for (final a in alerts ?? const <AlertInfo>[])
              ListTile(
                key: Key('alert-${a.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _icon(a.kind),
                  color: a.isUnread
                      ? theme.colorScheme.error
                      : theme.disabledColor,
                ),
                title: Text(
                  alertLabel(a),
                  style: a.isUnread
                      ? const TextStyle(fontWeight: FontWeight.w600)
                      : null,
                ),
                subtitle: Text(agoText(a.createdAt, now)),
                trailing: a.isUnread
                    ? const Icon(Icons.fiber_manual_record, size: 12)
                    : null,
                onTap: a.isUnread && !_busy ? () => _markRead([a]) : null,
              ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Text(
                'Chỉ có loại sự kiện và thời điểm, không có nội dung hay vị trí. '
                'Cảnh báo "mất kết nối" do máy chủ tự phát hiện khi máy con không liên lạc quá 24 giờ.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(String kind) => switch (kind) {
    AlertKind.timeChanged => Icons.schedule_rounded,
    AlertKind.appUninstallAttempt => Icons.delete_forever_rounded,
    AlertKind.accessibilityOff => Icons.accessibility_new_rounded,
    AlertKind.deviceAdminOff => Icons.admin_panel_settings_rounded,
    AlertKind.permissionMissing => Icons.warning_amber_rounded,
    AlertKind.offline => Icons.wifi_off_rounded,
    _ => Icons.notifications_active_rounded,
  };
}
