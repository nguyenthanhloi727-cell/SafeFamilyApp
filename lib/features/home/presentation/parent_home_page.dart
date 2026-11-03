import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/alerts/activity_seen.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/child_status_text.dart';
import '../../../core/network/connection_session.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/feature_card.dart';
import '../../app_lock/presentation/app_lock_page.dart';
import '../../connection/presentation/child_requests_page.dart';
import '../../connection/presentation/connection_page.dart';
import '../../connection/presentation/device_activity_page.dart';
import '../../connection/presentation/remote_monitor_page.dart';
import '../../new_app/presentation/new_apps_page.dart';
import '../../report/presentation/report_page.dart';
import '../../report/presentation/usage_summary_card.dart';
import '../../time_limit/presentation/pause_card.dart';
import '../../time_limit/presentation/time_limit_page.dart';

/// Trang chủ của MÁY MẸ (đã đăng nhập): quản lý máy con nằm ngay đây, không phải
/// chui vào Cá nhân → Bảo mật. Mọi thẻ bên dưới tác động lên máy con đã chọn.
class ParentHomePage extends StatefulWidget {
  const ParentHomePage({super.key});

  @override
  State<ParentHomePage> createState() => _ParentHomePageState();
}

class _ParentHomePageState extends State<ParentHomePage> {
  List<DeviceInfo>? _devices;
  String? _error;
  int _pendingRequests = 0;
  int _pendingNewApps = 0;
  int _unreadAlerts = 0;
  int _newActivity = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_reload());
  }

  DeviceInfo? get _selected {
    final id = ConnectionScope.maybeOf(context)?.selectedChildId;
    return _devices?.where((d) => d.id == id).firstOrNull;
  }

  Future<void> _reload() async {
    final api = ApiScope.maybeOf(context);
    final session = ConnectionScope.maybeOf(context);
    if (api == null || session == null) return;
    try {
      final devices = await api.listDevices();
      final chosen = session.selectedChildId;
      if (chosen != null && devices.every((d) => d.id != chosen)) {
        await session.selectChild(null);
      }
      if (session.selectedChildId == null && devices.length == 1) {
        await session.selectChild(devices.single.id);
      }
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _error = null;
      });
      unawaited(_loadCounts(api));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadCounts(ApiClient api) async {
    final id = _selected?.id;
    if (id == null) return;
    try {
      final requests = await api.getRequests(id, status: 'pending');
      final apps = await api.getDeviceApps(id, status: AppStatus.isNew);
      final alerts = await api.getAlerts(id);
      if (!mounted) return;
      setState(() {
        _pendingRequests = requests.length;
        _pendingNewApps = apps.length;
        _unreadAlerts = alerts.where((a) => a.isUnread).length;
      });
    } on ApiException {
      // Giữ số cũ; vào từng màn sẽ báo lỗi rõ hơn.
    }
    try {
      final seen = await ActivitySeen.get(id);
      final events = await api.getActivity(id);
      if (!mounted) return;
      setState(() => _newActivity = events.where((e) => e.id > seen).length);
    } on ApiException {
      // Như trên.
    }
  }

  Future<void> _open(String action, Widget page) async {
    final navigator = Navigator.of(context);
    if (!await ParentGate.parentArea(context, action)) return;
    await navigator.push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) unawaited(_reload());
  }

  Future<void> _pickChild() async {
    final devices = _devices ?? const <DeviceInfo>[];
    final session = ConnectionScope.maybeOf(context);
    final id = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in devices)
              ListTile(
                key: Key('pick-child-${d.id}'),
                leading: const Icon(Icons.child_care_rounded),
                title: Text(d.name),
                selected: session?.selectedChildId == d.id,
                onTap: () => Navigator.of(context).pop(d.id),
              ),
          ],
        ),
      ),
    );
    if (id == null || !mounted) return;
    await session?.selectChild(id);
    if (mounted) unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeFamily'),
        actions: [
          IconButton(
            key: const Key('open-connection'),
            tooltip: 'Kết nối gia đình',
            icon: const Icon(Icons.family_restroom_rounded),
            onPressed: () => _open('Kết nối gia đình', const ConnectionPage()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            ..._childHeader(theme, child),
            if (child != null) ...[
              const SizedBox(height: AppSpace.lg),
              FeatureCard(
                key: const Key('home-requests'),
                icon: Icons.mark_email_unread_rounded,
                title: 'Yêu cầu của con',
                subtitle: _pendingRequests > 0
                    ? '$_pendingRequests yêu cầu đang chờ bạn duyệt'
                    : 'Con xin thêm giờ, báo đã học xong',
                onTap: () =>
                    _open('Yêu cầu của con', ChildRequestsPage(device: child)),
              ),
              const SizedBox(height: AppSpace.md),
              FeatureCard(
                key: const Key('home-activity'),
                icon: Icons.history_rounded,
                title: 'Hoạt động của con',
                subtitle: _newActivity > 0
                    ? '$_newActivity hoạt động mới trên máy ${child.name}'
                    : 'Con mở app bị chặn, nhập sai khóa phụ huynh',
                onTap: () => _open(
                  'Hoạt động của con',
                  DeviceActivityPage(device: child),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              FeatureCard(
                key: const Key('home-block-apps'),
                icon: Icons.block_rounded,
                title: 'Chặn ứng dụng',
                subtitle:
                    'Chọn app trên máy ${child.name} không được mở, mở tạm khi cần',
                onTap: () => _open('Chặn ứng dụng', const AppLockPage()),
              ),
              const SizedBox(height: AppSpace.md),
              FeatureCard(
                key: const Key('home-time-limit'),
                icon: Icons.hourglass_bottom_rounded,
                title: 'Giới hạn thời gian',
                subtitle: 'Số phút dùng máy mỗi ngày, tổng và từng app',
                onTap: () => _open('Giới hạn thời gian', const TimeLimitPage()),
              ),
              const SizedBox(height: AppSpace.md),
              FeatureCard(
                key: const Key('home-new-apps'),
                icon: Icons.new_releases_outlined,
                title: 'Duyệt app mới cài',
                subtitle: _pendingNewApps > 0
                    ? '$_pendingNewApps app mới đang chờ bạn duyệt'
                    : 'App con vừa cài bị chặn cho tới khi bạn cho phép',
                onTap: () => _open(
                  'Duyệt app mới cài',
                  NewAppsPage(remoteDevice: child),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              const PauseCard(),
              const SizedBox(height: AppSpace.md),
              UsageSummaryCard(
                onTap: () =>
                    _open('Báo cáo thời gian dùng', const ReportPage()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _childHeader(ThemeData theme, DeviceInfo? child) {
    if (_devices == null) {
      return [
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton(onPressed: _reload, child: const Text('Thử lại')),
        ] else
          const Center(child: CircularProgressIndicator()),
      ];
    }
    if (_devices!.isEmpty) {
      return [
        FeatureCard(
          key: const Key('home-pair-child'),
          icon: Icons.add_link_rounded,
          title: 'Chưa có máy con nào',
          subtitle: 'Tạo mã ghép đôi rồi nhập vào máy của con',
          onTap: () => _open('Kết nối gia đình', const ConnectionPage()),
        ),
      ];
    }
    if (child == null) {
      return [
        FeatureCard(
          key: const Key('home-pick-child'),
          icon: Icons.child_care_rounded,
          title: 'Chọn máy con để quản lý',
          subtitle: 'Có ${_devices!.length} máy con đã ghép',
          onTap: _pickChild,
        ),
      ];
    }
    final seen = child.lastSeenAt == null
        ? 'Chưa thấy hoạt động'
        : 'Hoạt động ${agoText(child.lastSeenAt!.toLocal())}';
    final notes = [
      if (_unreadAlerts > 0) '$_unreadAlerts cảnh báo chưa đọc',
      if (_pendingRequests > 0) '$_pendingRequests yêu cầu chờ duyệt',
    ];
    return [
      Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('home-child-card'),
          onTap: () =>
              _open('Xem máy ${child.name}', RemoteMonitorPage(device: child)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              children: [
                const Icon(Icons.child_care_rounded, size: 36),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(child.name, style: theme.textTheme.titleLarge),
                      Text(seen),
                      if (notes.isNotEmpty)
                        Text(
                          notes.join(' · '),
                          style: TextStyle(color: theme.colorScheme.error),
                        )
                      else
                        const Text('Vị trí, hàng rào, cảnh báo, điều khiển'),
                    ],
                  ),
                ),
                if ((_devices?.length ?? 0) > 1)
                  IconButton(
                    key: const Key('switch-child'),
                    tooltip: 'Đổi máy con',
                    icon: const Icon(Icons.swap_horiz_rounded),
                    onPressed: _pickChild,
                  ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}
