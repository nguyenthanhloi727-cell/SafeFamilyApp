import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/connection_session.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../data/family_platform.dart';
import 'remote_monitor_page.dart';

/// "Kết nối gia đình": máy mẹ tạo mã ghép đôi, xem/hủy ghép máy con;
/// máy con xem trạng thái. Mọi thao tác ngắt kết nối đều qua khóa phụ huynh.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, this.family = const MethodChannelFamily()});

  final FamilyPlatform family;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  List<DeviceInfo>? _devices;
  PairingCode? _code;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_devices == null &&
        ConnectionScope.of(context).mode == ConnectionMode.parent) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final api = ApiScope.of(context);
    final session = ConnectionScope.of(context);
    try {
      final devices = await api.listDevices();
      // Máy con đã chọn bị hủy ghép → bỏ chọn; chỉ có một máy thì chọn luôn.
      final chosen = session.selectedChildId;
      if (chosen != null && devices.every((d) => d.id != chosen)) {
        await session.selectChild(null);
      }
      if (session.selectedChildId == null && devices.length == 1) {
        await session.selectChild(devices.single.id);
      }
      if (mounted) setState(() => _devices = devices);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _createCode() async {
    final api = ApiScope.of(context);
    setState(() => _busy = true);
    try {
      final code = await api.createPairingCode();
      if (mounted) setState(() => _code = code);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unpair(DeviceInfo d) async {
    final api = ApiScope.of(context);
    if (!await ParentGate.always(context, 'Hủy ghép ${d.name}')) return;
    try {
      await api.unpairDevice(d.id);
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<void> _disconnect() async {
    final session = ConnectionScope.of(context);
    final navigator = Navigator.of(context);
    if (!await ParentGate.always(context, 'Ngắt kết nối gia đình')) return;
    await session.reset();
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = ConnectionScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kết nối gia đình')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: switch (session.mode) {
          ConnectionMode.parent => _parentBody(session),
          ConnectionMode.child => [
            const ListTile(
              leading: Icon(Icons.link_rounded),
              title: Text('Đã kết nối với máy mẹ'),
              subtitle: Text(
                'Máy mẹ đặt luật, máy này tự chặn theo luật đã tải về.',
              ),
            ),
            LocationPermissionTile(platform: widget.family),
            _disconnectButton(),
          ],
          _ => [
            const ListTile(
              leading: Icon(Icons.phone_android_rounded),
              title: Text('Đang dùng một máy'),
              subtitle: Text('Chưa kết nối với máy nào khác.'),
            ),
            _disconnectButton(label: 'Chọn lại vai trò'),
          ],
        },
      ),
    );
  }

  Widget _disconnectButton({String label = 'Ngắt kết nối'}) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.lg),
    child: OutlinedButton(
      key: const Key('disconnect'),
      onPressed: _disconnect,
      child: Text(label),
    ),
  );

  List<Widget> _parentBody(ConnectionSession session) {
    final code = _code;
    return [
      ListTile(
        leading: const Icon(Icons.account_circle_rounded),
        title: Text(session.email ?? 'Máy mẹ'),
        subtitle: const Text('Máy mẹ'),
      ),
      const SizedBox(height: AppSpace.md),
      FilledButton.icon(
        key: const Key('create-code'),
        onPressed: _busy ? null : _createCode,
        icon: const Icon(Icons.pin_rounded),
        label: const Text('Tạo mã ghép đôi'),
      ),
      if (code != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
          child: Column(
            children: [
              SelectableText(
                code.code,
                key: const Key('pair-code-value'),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              Text('Nhập mã này trên máy con trong 10 phút (dùng một lần).'),
            ],
          ),
        ),
      const SizedBox(height: AppSpace.lg),
      Text('Máy con đã ghép', style: Theme.of(context).textTheme.titleMedium),
      if (_error != null) Text(_error!),
      if (_devices != null && _devices!.isEmpty)
        const Text('Chưa có máy con nào.'),
      for (final d in _devices ?? const <DeviceInfo>[])
        ListTile(
          key: Key('device-${d.id}'),
          leading: const Icon(Icons.child_care_rounded),
          title: Text(d.name),
          selected: ConnectionScope.of(context).selectedChildId == d.id,
          onTap: () {
            ConnectionScope.of(context).selectChild(d.id);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RemoteMonitorPage(device: d),
              ),
            );
          },
          subtitle: Text(
            d.lastSeenAt == null
                ? 'Chưa thấy hoạt động'
                : 'Hoạt động lần cuối: ${d.lastSeenAt!.toLocal()} · chạm để xem vị trí / điều khiển',
          ),
          trailing: IconButton(
            tooltip: 'Hủy ghép',
            icon: const Icon(Icons.link_off_rounded),
            onPressed: () => _unpair(d),
          ),
        ),
      _disconnectButton(label: 'Đăng xuất máy mẹ'),
    ];
  }
}

/// Máy con: trạng thái quyền vị trí (cần "Luôn cho phép" để vị trí và hàng rào chạy
/// khi app đóng) và nút xin quyền theo 2 bước. Thông báo rõ trẻ đang chia sẻ vị trí.
class LocationPermissionTile extends StatefulWidget {
  const LocationPermissionTile({super.key, required this.platform});

  final FamilyPlatform platform;

  @override
  State<LocationPermissionTile> createState() => _LocationPermissionTileState();
}

class _LocationPermissionTileState extends State<LocationPermissionTile>
    with WidgetsBindingObserver {
  LocationPermissionStatus _status = const LocationPermissionStatus();

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
    final s = await widget.platform.locationStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _ask() async {
    if (!_status.foreground) {
      await widget.platform.requestLocation();
    } else {
      await widget.platform.requestBackgroundLocation();
    }
    // Hộp thoại quyền trả về qua vòng đời; kiểm tra lại sau một nhịp.
    await Future<void>.delayed(const Duration(seconds: 1));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final full = _status.foreground && _status.background;
    return ListTile(
      key: const Key('location-permission'),
      leading: Icon(
        full ? Icons.location_on_rounded : Icons.location_off_rounded,
      ),
      title: Text(
        full
            ? 'Đang chia sẻ vị trí với máy mẹ'
            : _status.foreground
            ? 'Cần chọn "Luôn cho phép" vị trí'
            : 'Chưa cấp quyền vị trí',
      ),
      subtitle: const Text(
        'Máy mẹ xem được vị trí máy này và nhận báo khi vào/ra khu vực đã đặt. '
        'Thông báo trên thanh trạng thái luôn hiện khi đang chia sẻ.',
      ),
      trailing: full
          ? null
          : TextButton(
              key: const Key('location-grant'),
              onPressed: _ask,
              child: const Text('Cấp quyền'),
            ),
    );
  }
}
