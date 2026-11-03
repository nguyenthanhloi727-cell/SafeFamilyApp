import 'package:flutter/material.dart';

import '../../../core/alerts/activity_seen.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/child_status_text.dart';
import '../../../core/theme/app_tokens.dart';

/// "Hoạt động của máy con": con mở app đang bị chặn, nhập sai khóa phụ huynh, phụ huynh mở khóa. Chỉ có loại
/// sự kiện, tên app và giờ, không nội dung. Mới nhất trước, nhóm theo ngày.
///
/// Mở màn này là đã xem: mốc "đã xem" nhảy tới dòng mới nhất (để Trang chủ hết báo số mới). Dòng mới hơn mốc cũ
/// được tô đậm để mẹ biết cái nào mới.
class DeviceActivityPage extends StatefulWidget {
  const DeviceActivityPage({super.key, required this.device});

  final DeviceInfo device;

  @override
  State<DeviceActivityPage> createState() => _DeviceActivityPageState();
}

class _DeviceActivityPageState extends State<DeviceActivityPage> {
  List<ActivityInfo>? _events;
  Map<String, String> _labels = const {};
  int _seenBefore = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final api = ApiScope.of(context);
    final id = widget.device.id;
    try {
      final seen = _events == null ? await ActivitySeen.get(id) : _seenBefore;
      final list = await api.getActivity(id);
      final labels = await _loadLabels(api, list);
      if (!mounted) return;
      setState(() {
        _seenBefore = seen;
        _events = list.reversed.toList(); // Mới nhất trước.
        _labels = labels;
        _error = null;
      });
      if (list.isNotEmpty) {
        await ActivitySeen.set(
          id,
          list.map((e) => e.id).reduce((a, b) => a > b ? a : b),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Tên app thân thiện cho các tên gói trong nhật ký. Lỗi thì thôi, hiện tên gói.
  Future<Map<String, String>> _loadLabels(
    ApiClient api,
    List<ActivityInfo> events,
  ) async {
    if (events.every((e) => e.kind != ActivityKind.blockedAppOpen)) {
      return _labels;
    }
    try {
      final apps = await api.getDeviceApps(widget.device.id);
      return {for (final a in apps) a.packageName: a.label};
    } on ApiException {
      return _labels;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = _events;
    final now = DateTime.now();
    final rows = <Widget>[];
    String? lastDay;
    for (final e in events ?? const <ActivityInfo>[]) {
      final local = e.time.toLocal();
      final day = dayHeading(local, now);
      if (day != lastDay) {
        lastDay = day;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpace.md,
              bottom: AppSpace.xs,
            ),
            child: Text(day, style: theme.textTheme.titleSmall),
          ),
        );
      }
      final isNew = e.id > _seenBefore;
      rows.add(
        ListTile(
          key: Key('activity-${e.id}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _icon(e.kind),
            color: e.kind == ActivityKind.parentUnlocked
                ? theme.disabledColor
                : theme.colorScheme.error,
          ),
          title: Text(
            activityLabel(e, _labels),
            style: isNew ? const TextStyle(fontWeight: FontWeight.w600) : null,
          ),
          subtitle: Text('${_hhmm(local)} · ${agoText(local, now)}'),
          trailing: isNew
              ? const Icon(Icons.fiber_manual_record, size: 12)
              : null,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Hoạt động của ${widget.device.name}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (events == null && _error == null)
              const LinearProgressIndicator(),
            if (events != null && events.isEmpty)
              const Text('Chưa có hoạt động nào.'),
            ...rows,
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Text(
                'Chỉ có loại sự kiện, tên app và giờ, không có nội dung. Nhật ký giữ 30 ngày.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static IconData _icon(String kind) => switch (kind) {
    ActivityKind.blockedAppOpen => Icons.block_rounded,
    ActivityKind.parentAuthFailed => Icons.lock_outline_rounded,
    ActivityKind.parentUnlocked => Icons.lock_open_rounded,
    _ => Icons.history_rounded,
  };
}
