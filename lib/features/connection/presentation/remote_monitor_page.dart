import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/child_status_text.dart';
import '../../../core/network/connection_session.dart';
import '../../../core/network/policy_sync.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../new_app/presentation/new_apps_page.dart';
import 'child_requests_page.dart';
import 'device_alerts_page.dart';
import 'sent_commands_page.dart';

/// Máy mẹ xem và điều khiển một máy con: vị trí, hàng rào địa lý, lệnh nhanh
/// (khóa/mở khóa, giờ học...) và gửi luật (giới hạn thời gian + khóa ứng dụng).
///
/// Không có FCM nên màn này tự hỏi lại server mỗi [refreshEvery] khi đang mở;
/// lệnh gửi đi thì máy con nhận ở lần hỏi kế (tối đa ~5 phút).
class RemoteMonitorPage extends StatefulWidget {
  const RemoteMonitorPage({
    super.key,
    required this.device,
    this.refreshEvery = const Duration(seconds: 60),
  });

  final DeviceInfo device;
  final Duration refreshEvery;

  @override
  State<RemoteMonitorPage> createState() => _RemoteMonitorPageState();
}

class _RemoteMonitorPageState extends State<RemoteMonitorPage> {
  DeviceStatusInfo? _status;
  int? _pendingRequests;
  int? _pendingNewApps;
  int? _unreadAlerts;
  LocationInfo? _location;
  bool _locationSharing = true;
  GeofenceSet? _fences;
  List<GeofenceEventInfo> _events = const [];
  String? _error;
  bool _loaded = false;
  Timer? _timer;

  int get _id => widget.device.id;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.refreshEvery, (_) => _reload());
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final api = ApiScope.of(context);
    // Trạng thái tải riêng: lỗi ở đây không được làm mất vị trí / hàng rào.
    unawaited(_loadStatus(api));
    unawaited(_loadPendingRequests(api));
    try {
      // Cờ chia sẻ trước: tắt thì không hỏi vị trí (server cũng từ chối 403).
      final sharing = await api.getLocationSharing(_id);
      final results = await Future.wait<Object?>([
        sharing ? api.getLastLocation(_id) : Future<LocationInfo?>.value(),
        api.getGeofences(_id),
        api.getGeofenceEvents(_id),
      ]);
      if (!mounted) return;
      setState(() {
        _locationSharing = sharing;
        _location = results[0] as LocationInfo?;
        _fences = results[1] as GeofenceSet;
        _events = (results[2] as List<GeofenceEventInfo>).reversed.toList();
        _error = null;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (e.isForbidden && mounted) {
        // Mẹ tắt ở máy khác giữa hai lần gọi: hiện "đang tắt" thay vì báo lỗi.
        setState(() {
          _locationSharing = false;
          _location = null;
        });
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.message;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _loadStatus(ApiClient api) async {
    try {
      final status = await api.getDeviceStatus(_id);
      if (mounted) setState(() => _status = status);
    } on ApiException {
      // Giữ trạng thái cũ; màn vẫn dùng được.
    }
  }

  Future<void> _loadPendingRequests(ApiClient api) async {
    try {
      final list = await api.getRequests(_id, status: 'pending');
      if (mounted) setState(() => _pendingRequests = list.length);
    } on ApiException {
      // Giữ số cũ; vào màn yêu cầu sẽ báo lỗi rõ hơn.
    }
    try {
      final apps = await api.getDeviceApps(_id, status: AppStatus.isNew);
      if (mounted) setState(() => _pendingNewApps = apps.length);
    } on ApiException {
      // Giữ số cũ; vào màn duyệt app sẽ báo lỗi rõ hơn.
    }
    try {
      final alerts = await api.getAlerts(_id);
      if (mounted) {
        setState(() => _unreadAlerts = alerts.where((a) => a.isUnread).length);
      }
    } on ApiException {
      // Giữ số cũ; vào màn cảnh báo sẽ báo lỗi rõ hơn.
    }
  }

  // ---- Lệnh ----

  Future<void> _command(String label, String type, {int? minutes}) async {
    final api = ApiScope.of(context);
    if (!await ParentGate.always(context, label)) return;
    try {
      await api.sendCommand(
        _id,
        type,
        payloadJson: minutes == null ? null : jsonEncode({'minutes': minutes}),
      );
      if (mounted) {
        showAppSnackBar(
          context,
          'Đã gửi lệnh "$label". Máy con nhận ở lần đồng bộ kế (tối đa vài phút).',
        );
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  /// Gửi luật của máy này (schema: `PolicySchema`). Lệch phiên bản thì
  /// `PolicySync` tải lại và hỏi mẹ, không ghi đè im lặng.
  Future<void> _pushPolicy() async {
    final sync = PolicySyncScope.maybeOf(context);
    if (sync == null) return;
    final session = ConnectionScope.maybeOf(context);
    if (!await ParentGate.always(context, 'Gửi luật cho máy con')) return;
    await session?.selectChild(_id);
    await sync.pushNow();
  }

  // ---- Quyền riêng tư vị trí (API-11) ----

  Future<void> _toggleSharing(bool on) async {
    final api = ApiScope.of(context);
    final label = on ? 'Bật chia sẻ vị trí' : 'Tắt chia sẻ vị trí';
    if (!await ParentGate.always(context, label)) return;
    try {
      final saved = await api.setLocationSharing(_id, on);
      if (!mounted) return;
      setState(() {
        _locationSharing = saved;
        if (!saved) _location = null;
      });
      showAppSnackBar(
        context,
        saved
            ? 'Đã bật chia sẻ vị trí. Máy con áp dụng ở lần đồng bộ kế (tối đa vài phút).'
            : 'Đã tắt chia sẻ vị trí. Máy con dừng gửi ở lần đồng bộ kế (tối đa vài phút).',
      );
      if (saved) await _reload();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<void> _deleteHistory() async {
    final api = ApiScope.of(context);
    if (!await ParentGate.always(context, 'Xóa lịch sử vị trí')) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lịch sử vị trí?'),
        content: const Text(
          'Toàn bộ vị trí đã lưu của máy con sẽ bị xóa khỏi máy chủ và không khôi phục được.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm-delete-locations'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await api.deleteLocationHistory(_id);
      if (!mounted) return;
      setState(() => _location = null);
      showAppSnackBar(context, 'Đã xóa lịch sử vị trí.');
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  // ---- Hàng rào ----

  Future<void> _addFence() async {
    final fence = await showDialog<GeofenceInfo>(
      context: context,
      builder: (_) => _FenceDialog(lastKnown: _location),
    );
    if (fence == null || !mounted) return;
    await _saveFences([...?_fences?.geofences, fence], 'Thêm hàng rào "${fence.name}"');
  }

  Future<void> _removeFence(GeofenceInfo f) => _saveFences([
    for (final g in _fences?.geofences ?? const <GeofenceInfo>[])
      if (g.id != f.id) g,
  ], 'Xóa hàng rào "${f.name}"');

  Future<void> _saveFences(List<GeofenceInfo> next, String action) async {
    final api = ApiScope.of(context);
    final version = _fences?.version ?? 0;
    if (!await ParentGate.always(context, action)) return;
    try {
      final saved = await api.putGeofences(_id, next, version);
      if (mounted) setState(() => _fences = saved);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
      await _reload();
    }
  }

  Future<void> _openMap(LocationInfo l) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${l.lat},${l.lng}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      showAppSnackBar(context, 'Không mở được bản đồ.');
    }
  }

  // ---- Giao diện ----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          Text('Trạng thái máy con', style: theme.textTheme.titleMedium),
          _statusTile(theme),
          const SizedBox(height: AppSpace.lg),
          Text('Vị trí', style: theme.textTheme.titleMedium),
          SwitchListTile(
            key: const Key('location-sharing'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Chia sẻ vị trí'),
            subtitle: Text(
              _locationSharing
                  ? 'Máy con gửi vị trí cho bố mẹ.'
                  : 'Đã tắt: máy con không gửi vị trí.',
            ),
            value: _locationSharing,
            onChanged: _loaded ? _toggleSharing : null,
          ),
          _locationTile(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('delete-locations'),
              onPressed: _loaded ? _deleteHistory : null,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Xóa lịch sử vị trí'),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(child: Text('Hàng rào địa lý', style: theme.textTheme.titleMedium)),
              TextButton.icon(
                key: const Key('add-fence'),
                onPressed: _loaded ? _addFence : null,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Thêm'),
              ),
            ],
          ),
          if (_loaded && (_fences?.geofences.isEmpty ?? true))
            const Text('Chưa có hàng rào nào.'),
          for (final f in _fences?.geofences ?? const <GeofenceInfo>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_rounded),
              title: Text(f.name),
              subtitle: Text('Bán kính ${f.radiusM.round()} m'),
              trailing: IconButton(
                tooltip: 'Xóa',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _removeFence(f),
              ),
            ),
          const SizedBox(height: AppSpace.md),
          Text('Vào / ra gần đây', style: theme.textTheme.titleSmall),
          if (_loaded && _events.isEmpty) const Text('Chưa có sự kiện.'),
          for (final e in _events.take(20))
            ListTile(
              key: Key('event-${e.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.isExit ? Icons.logout_rounded : Icons.login_rounded),
              title: Text(e.isExit ? 'Con đã rời ${e.name}' : 'Con đã đến ${e.name}'),
              subtitle: Text(_ago(e.time)),
            ),
          const SizedBox(height: AppSpace.lg),
          Text('Điều khiển máy con', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              _action('Khóa 60 phút', Icons.lock_rounded, 'lock', minutes: 60),
              _action('Mở khóa', Icons.lock_open_rounded, 'unlock'),
              _action('Giờ học 30 phút', Icons.school_rounded, 'study_start', minutes: 30),
              _action('Dừng giờ học', Icons.stop_circle_rounded, 'study_stop'),
              _action('Duyệt đã học xong', Icons.check_circle_rounded, 'study_approve'),
              _action('Từ chối', Icons.cancel_rounded, 'study_reject'),
              _action('Tắt giới hạn hôm nay', Icons.timer_off_rounded, 'disable_limit_today'),
              _action('Bật lại giới hạn', Icons.timer_rounded, 'enable_limit_today'),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          OutlinedButton.icon(
            key: const Key('child-requests'),
            onPressed: () async {
              final api = ApiScope.of(context);
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChildRequestsPage(device: widget.device),
                ),
              );
              if (mounted) unawaited(_loadPendingRequests(api));
            },
            icon: const Icon(Icons.mark_email_unread_rounded),
            label: Text(
              (_pendingRequests ?? 0) > 0
                  ? 'Yêu cầu của con ($_pendingRequests chờ duyệt)'
                  : 'Yêu cầu của con',
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            key: const Key('new-apps'),
            onPressed: () async {
              final api = ApiScope.of(context);
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NewAppsPage(remoteDevice: widget.device),
                ),
              );
              if (mounted) unawaited(_loadPendingRequests(api));
            },
            icon: const Icon(Icons.new_releases_outlined),
            label: Text(
              (_pendingNewApps ?? 0) > 0
                  ? 'App mới cài ($_pendingNewApps chờ duyệt)'
                  : 'App mới cài',
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            key: const Key('device-alerts'),
            onPressed: () async {
              final api = ApiScope.of(context);
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeviceAlertsPage(device: widget.device),
                ),
              );
              if (mounted) unawaited(_loadPendingRequests(api));
            },
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(
              (_unreadAlerts ?? 0) > 0
                  ? 'Cảnh báo ($_unreadAlerts chưa đọc)'
                  : 'Cảnh báo của máy con',
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            key: const Key('sent-commands'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SentCommandsPage(device: widget.device),
              ),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('Lệnh đã gửi'),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            key: const Key('push-policy'),
            onPressed: _pushPolicy,
            icon: const Icon(Icons.cloud_upload_rounded),
            label: const Text('Gửi luật của máy này (giờ + khóa app)'),
          ),
        ],
      ),
    );
  }

  Widget _action(String label, IconData icon, String type, {int? minutes}) =>
      ActionChip(
        key: Key('cmd-$type'),
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onPressed: () => _command(label, type, minutes: minutes),
      );

  /// Trạng thái máy con: lần cuối thấy, tạm dừng, giờ học, pin, quyền còn thiếu.
  /// Máy con chưa báo lần nào (mới ghép / bản app cũ) thì nói rõ là chưa có, không đoán.
  Widget _statusTile(ThemeData theme) {
    final s = _status;
    if (s == null) {
      return _loaded
          ? const Text('Chưa tải được trạng thái.')
          : const SizedBox.shrink();
    }
    final seen = s.lastSeenAt;
    final details = <String>[
      if (s.hasReported) ...[
        s.isPaused ? 'Đang tạm dừng' : 'Không tạm dừng',
        if (s.studyActive) 'Đang trong giờ học',
        if (s.batteryPercent != null) 'Pin ${s.batteryPercent}%',
      ] else
        'Máy con chưa báo trạng thái (cần bản app mới nhất)',
    ];
    return Column(
      key: const Key('child-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            s.isPaused ? Icons.pause_circle_rounded : Icons.phone_android_rounded,
          ),
          title: Text(
            seen == null
                ? 'Chưa thấy máy con kết nối'
                : 'Lần cuối: ${agoText(seen)}',
          ),
          subtitle: Text(details.join(' · ')),
        ),
        if (s.permissionsMissing.isNotEmpty)
          ListTile(
            key: const Key('child-missing-permissions'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
            ),
            title: const Text('Máy con còn thiếu quyền'),
            subtitle: Text(s.permissionsMissing.map(permissionLabel).join(', ')),
          ),
      ],
    );
  }

  Widget _locationTile() {
    final l = _location;
    if (!_loaded) return const LinearProgressIndicator();
    if (!_locationSharing) {
      return const ListTile(
        key: Key('location-off'),
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.location_off_rounded),
        title: Text('Đang tắt chia sẻ vị trí'),
        subtitle: Text('Máy con không gửi vị trí. Bật công tắc để chia sẻ lại.'),
      );
    }
    if (l == null) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.location_off_rounded),
        title: Text('Chưa có vị trí'),
        subtitle: Text('Máy con chưa gửi vị trí (chưa cấp quyền, tắt mạng hoặc mới ghép).'),
      );
    }
    return ListTile(
      key: const Key('last-location'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.my_location_rounded),
      title: Text('${l.lat.toStringAsFixed(5)}, ${l.lng.toStringAsFixed(5)}'),
      subtitle: Text('Cập nhật lần cuối: ${_ago(l.time)} · sai số ~${l.accuracy.round()} m'),
      trailing: IconButton(
        tooltip: 'Mở bản đồ',
        icon: const Icon(Icons.map_rounded),
        onPressed: () => _openMap(l),
      ),
    );
  }

  static String _ago(DateTime t) => agoText(t);
}

class _FenceDialog extends StatefulWidget {
  const _FenceDialog({this.lastKnown});

  final LocationInfo? lastKnown;

  @override
  State<_FenceDialog> createState() => _FenceDialogState();
}

class _FenceDialogState extends State<_FenceDialog> {
  final _name = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _radius = TextEditingController(text: '150');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    super.dispose();
  }

  void _useLast() {
    final l = widget.lastKnown;
    if (l == null) return;
    _lat.text = l.lat.toStringAsFixed(6);
    _lng.text = l.lng.toStringAsFixed(6);
  }

  void _submit() {
    final name = _name.text.trim();
    final lat = double.tryParse(_lat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.trim().replaceAll(',', '.'));
    final radius = double.tryParse(_radius.text.trim());
    if (name.isEmpty) return setState(() => _error = 'Hãy đặt tên cho khu vực.');
    if (lat == null || lat < -90 || lat > 90 || lng == null || lng < -180 || lng > 180) {
      return setState(() => _error = 'Tọa độ chưa hợp lệ.');
    }
    if (radius == null || radius < 100 || radius > 10000) {
      return setState(() => _error = 'Bán kính từ 100 m đến 10 km (GPS sai số 10–30 m).');
    }
    Navigator.of(context).pop(
      GeofenceInfo(name: name, lat: lat, lng: lng, radiusM: radius),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm hàng rào'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('fence-name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Tên khu vực',
                hintText: 'Trường cấp 2 của con',
              ),
            ),
            TextField(
              key: const Key('fence-lat'),
              controller: _lat,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Vĩ độ (lat)'),
            ),
            TextField(
              key: const Key('fence-lng'),
              controller: _lng,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Kinh độ (lng)'),
            ),
            if (widget.lastKnown != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('fence-use-last'),
                  onPressed: _useLast,
                  child: const Text('Dùng vị trí hiện tại của con'),
                ),
              ),
            TextField(
              key: const Key('fence-radius'),
              controller: _radius,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Bán kính (mét)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('fence-save'),
          onPressed: _submit,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
