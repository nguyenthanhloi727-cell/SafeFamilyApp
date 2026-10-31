import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/policy_sync.dart';
import '../../../core/network/remote_commands.dart';
import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/status_banner.dart';
import '../app_lock_config.dart';
import '../data/app_lock_platform.dart';
import 'app_lock_controller.dart';
import 'app_lock_setup_page.dart';

/// Khóa ứng dụng: danh sách app đã cài, tìm kiếm, công tắc Chặn, mở tạm.
/// Đã xác thực lúc vào màn (phiên phụ huynh) nên chặn / bỏ chặn / mở tạm
/// dùng [ParentGate.parentArea], không hỏi lại.
///
/// [onlyLocked] = true: chỉ liệt kê app đang bị chặn (thẻ "Ứng dụng bị chặn"
/// ở trang chủ); chọn app để chặn thì dùng màn đầy đủ.
class AppLockPage extends StatefulWidget {
  const AppLockPage({super.key, this.onlyLocked = false, this.footer});

  final bool onlyLocked;

  /// Phần đặt dưới danh sách ở chế độ [onlyLocked] (lịch chặn theo giờ).
  final Widget? footer;

  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage> {
  final _search = TextEditingController();
  String _query = '';
  bool _showSystemApps = false;
  bool _requestedApps = false;

  /// Chế độ mẹ + đã chọn máy con: app đang mở tạm TRÊN MÁY CON (máy con tự báo) và hạn chặn lại.
  Map<String, DateTime> _remoteUnlocked = const {};

  /// App đã gửi lệnh "chặn lại ngay" mà máy con chưa báo là đã chặn.
  final Set<String> _relockSent = {};
  bool _requestedRemote = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppLockScope.maybeOf(context);
    if (controller != null && !_requestedApps) {
      _requestedApps = true;
      controller.loadApps();
    }
    if (!_requestedRemote) {
      _requestedRemote = true;
      _loadRemoteUnlocked();
    }
  }

  Future<void> _loadRemoteUnlocked() async {
    final child = RemoteCommands.targetOf(context);
    final api = ApiScope.maybeOf(context);
    if (child == null || api == null) return;
    try {
      final status = await api.getDeviceStatus(child);
      if (!mounted) return;
      setState(() {
        _remoteUnlocked = {
          for (final t in status.tempUnlocked)
            if (t.until.isAfter(DateTime.now())) t.package: t.until.toLocal(),
        };
        // App máy con đã báo chặn lại (không còn trong danh sách) thì bỏ cờ "đã gửi lệnh".
        _relockSent.removeWhere((p) => !_remoteUnlocked.containsKey(p));
      });
    } on ApiException {
      // Không biết trạng thái mở tạm của máy con: không hiện nút "chặn lại ngay", mẹ thử lại sau.
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _setLocked(
    AppLockController controller,
    InstalledApp app,
    bool locked,
  ) async {
    final action = locked ? 'Chặn ${app.name}' : 'Bỏ chặn ${app.name}';
    if (!await ParentGate.parentArea(context, action)) return;
    final ok = await controller.setLocked(app.packageName, locked);
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(context, 'Chưa ${action.toLowerCase()} được. Thử lại.');
    } else {
      // Danh sách khóa đổi → đẩy lên máy con nếu máy mẹ đã chọn máy con.
      PolicySyncScope.notifyChanged(context);
      if (locked) showAppSnackBar(context, 'Đã chặn ${app.name}.');
    }
  }

  Future<void> _unlockTemporarily(
    AppLockController controller,
    InstalledApp app,
  ) async {
    final action = 'Mở tạm $tempUnlockMinutes phút: ${app.name}';
    if (!await ParentGate.parentArea(context, action)) return;
    if (!mounted) return;
    // Chế độ mẹ + đã chọn máy con: mở tạm trên máy con, không đụng danh sách của máy mẹ.
    final child = RemoteCommands.targetOf(context);
    if (child != null) {
      await RemoteCommands.send(
        context,
        child,
        'app_unlock_temp',
        payloadJson: RemoteCommands.unlockTempPayload(
          app.packageName,
          tempUnlockMinutes,
        ),
        done:
            'Đã gửi lệnh mở tạm ${app.name} $tempUnlockMinutes phút. Máy con nhận ở lần đồng bộ kế.',
      );
      return;
    }
    try {
      final until = await controller.unlockTemporarily(app.packageName);
      if (!mounted) return;
      showAppSnackBar(
        context,
        until == null
            ? 'Sắp nửa đêm, không mở tạm được. Tắt công tắc nếu muốn bỏ chặn.'
            : 'Đã mở ${app.name} tới ${_hhmm(until)}. Hết giờ tự chặn lại.',
      );
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Chưa mở tạm được. Kiểm tra quyền "Báo thức & lời nhắc".',
        );
      }
    }
  }

  Future<void> _relockNow(
    AppLockController controller,
    InstalledApp app,
  ) async {
    if (!await ParentGate.parentArea(context, 'Chặn lại ${app.name}')) return;
    if (!mounted) return;
    // Chế độ mẹ + đã chọn máy con: chặn lại trên máy con, không đụng danh sách của máy mẹ.
    final child = RemoteCommands.targetOf(context);
    if (child != null) {
      final sent = await RemoteCommands.send(
        context,
        child,
        'app_relock',
        payloadJson: RemoteCommands.packagePayload(app.packageName),
        done:
            'Đã gửi lệnh chặn lại ${app.name}. Máy con nhận ở lần đồng bộ kế.',
      );
      if (sent && mounted) setState(() => _relockSent.add(app.packageName));
      return;
    }
    try {
      await controller.relockNow(app.packageName);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Chưa chặn lại được. Thử lại.');
    }
  }

  void _openAllApps() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const AppLockPage()));

  void _openSetup() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const AppLockSetupPage()));

  @override
  Widget build(BuildContext context) {
    return ParentAreaGuard(child: _buildPage(context));
  }

  Widget _buildPage(BuildContext context) {
    final controller = AppLockScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onlyLocked ? 'Ứng dụng bị chặn' : 'Khóa ứng dụng'),
        actions: [
          IconButton(
            tooltip: 'Thiết lập khóa ứng dụng',
            onPressed: _openSetup,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: controller == null
          ? const Center(child: Text('Khóa ứng dụng không dùng được.'))
          : _body(context, controller),
    );
  }

  Widget _body(BuildContext context, AppLockController controller) {
    final apps = controller.apps;
    final header = <Widget>[
      if (controller.isLoaded && !controller.ready) ...[
        StatusBanner(
          type: StatusType.error,
          title: 'Chưa bật đủ quyền khóa ứng dụng',
          message: 'Thiếu quyền thì con vẫn mở được app bị chặn.',
          actions: [
            FilledButton(onPressed: _openSetup, child: const Text('Thiết lập')),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
      ],
      if (apps != null && !widget.onlyLocked)
        ..._youtubeQuickBlock(controller, apps),
      if (widget.onlyLocked) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                'Chặn thủ công',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: _openAllApps,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Chặn thêm'),
            ),
          ],
        ),
      ] else
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: InputDecoration(
            hintText: 'Tìm ứng dụng',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa tìm kiếm',
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      const SizedBox(height: AppSpace.sm),
      if (!widget.onlyLocked) ...[
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            label: const Text('Hiện cả app có sẵn của máy'),
            selected: _showSystemApps,
            onSelected: (value) => setState(() => _showSystemApps = value),
          ),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
    ];

    if (apps == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          ...header,
          const SizedBox(height: AppSpace.xl),
          Center(
            child: controller.appsFailed
                ? Column(
                    children: [
                      const Text('Không lấy được danh sách ứng dụng.'),
                      const SizedBox(height: AppSpace.sm),
                      OutlinedButton(
                        onPressed: controller.loadApps,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ],
      );
    }

    final visible = _filter(controller, apps);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      itemCount:
          header.length +
          (visible.isEmpty ? 1 : visible.length) +
          (widget.onlyLocked ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < header.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: header[index],
          );
        }
        final listIndex = index - header.length;
        if (widget.onlyLocked &&
            listIndex == (visible.isEmpty ? 1 : visible.length)) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.xl,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: widget.footer ?? const SizedBox.shrink(),
          );
        }
        if (visible.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Text(
              widget.onlyLocked && _query.isEmpty
                  ? 'Chưa chặn app nào. Bấm "Chặn thêm" để chọn app cần chặn.'
                  : 'Không có ứng dụng nào khớp.',
              textAlign: TextAlign.center,
            ),
          );
        }
        final app = visible[index - header.length];
        final remote = RemoteCommands.targetOf(context) != null;
        return _AppTile(
          app: app,
          controller: controller,
          // Chế độ mẹ: hạn mở tạm là của máy con, không phải của máy này.
          until: remote
              ? _remoteUnlocked[app.packageName]
              : controller.unlockedUntil(app.packageName),
          relockSent: _relockSent.contains(app.packageName),
          onChanged: (locked) => _setLocked(controller, app, locked),
          onUnlock: () => _unlockTemporarily(controller, app),
          onRelock: () => _relockNow(controller, app),
        );
      },
    );
  }

  /// App bị chặn lên đầu; app hệ thống ẩn trừ khi đang bị chặn hoặc bật lọc.
  List<InstalledApp> _filter(
    AppLockController controller,
    List<InstalledApp> apps,
  ) {
    final query = _query.toLowerCase();
    final result = [
      for (final app in apps)
        if ((widget.onlyLocked
                ? controller.isLocked(app.packageName)
                : _showSystemApps ||
                      !app.isSystemApp ||
                      controller.isLocked(app.packageName)) &&
            (query.isEmpty ||
                app.name.toLowerCase().contains(query) ||
                app.packageName.toLowerCase().contains(query)))
          app,
    ];
    result.sort((a, b) {
      final locked =
          (controller.isLocked(b.packageName) ? 1 : 0) -
          (controller.isLocked(a.packageName) ? 1 : 0);
      return locked != 0
          ? locked
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  List<Widget> _youtubeQuickBlock(
    AppLockController controller,
    List<InstalledApp> apps,
  ) {
    final youtube = apps
        .where((app) => app.packageName == youtubePackage)
        .firstOrNull;
    if (youtube == null || controller.isLocked(youtubePackage)) return const [];
    return [
      FilledButton.icon(
        onPressed: controller.ready && !controller.isBusy(youtubePackage)
            ? () => _setLocked(controller, youtube, true)
            : null,
        icon: const Icon(Icons.smart_display_rounded),
        label: const Text('Chặn nhanh YouTube'),
      ),
      const SizedBox(height: AppSpace.lg),
    ];
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.controller,
    required this.until,
    required this.relockSent,
    required this.onChanged,
    required this.onUnlock,
    required this.onRelock,
  });

  final InstalledApp app;
  final AppLockController controller;
  final DateTime? until;
  final bool relockSent;
  final ValueChanged<bool> onChanged;
  final VoidCallback onUnlock;
  final VoidCallback onRelock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = controller.isLocked(app.packageName);
    final until = this.until;
    final busy = controller.isBusy(app.packageName);
    final icon = app.icon;

    return ListTile(
      minTileHeight: AppSize.listItemMin,
      leading: SizedBox.square(
        dimension: AppSize.avatarSm,
        child: icon == null
            ? const Icon(Icons.android_rounded)
            : Image.memory(icon, gaplessPlayback: true),
      ),
      title: Text(app.name),
      subtitle: until != null
          ? Text(
              relockSent
                  ? 'Đã gửi lệnh chặn lại, chờ máy con (đang mở tạm tới ${_hhmm(until)})'
                  : 'Đang mở tạm tới ${_hhmm(until)}',
              style: TextStyle(color: theme.colorScheme.secondary),
            )
          : locked
          ? Text('Đang chặn', style: TextStyle(color: theme.colorScheme.error))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const Padding(
              padding: EdgeInsets.all(AppSpace.md),
              child: SizedBox.square(
                dimension: AppSize.icon,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (until != null)
            IconButton(
              tooltip: 'Chặn lại ngay',
              onPressed: relockSent ? null : onRelock,
              icon: const Icon(Icons.lock_outline_rounded),
            )
          else if (locked)
            IconButton(
              tooltip: 'Mở tạm $tempUnlockMinutes phút',
              onPressed: controller.ready ? onUnlock : null,
              icon: const Icon(Icons.timer_outlined),
            ),
          Switch(
            value: locked,
            onChanged: busy || (!locked && !controller.ready)
                ? null
                : onChanged,
          ),
        ],
      ),
    );
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
