import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_banner.dart';
import '../data/new_app_platform.dart';

/// Duyệt app mới cài: app lạ bị chặn cho tới khi phụ huynh xác thực và cho phép.
class NewAppsPage extends StatefulWidget {
  const NewAppsPage({super.key, this.platform = const MethodChannelNewApp()});

  final NewAppPlatform platform;

  @override
  State<NewAppsPage> createState() => _NewAppsPageState();
}

class _NewAppsPageState extends State<NewAppsPage> with WidgetsBindingObserver {
  bool? _enabled;
  bool _notifications = true;
  List<PendingApp> _pending = const [];
  List<PendingApp> _rejected = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final enabled = await widget.platform.isEnabled();
    final pending = await widget.platform.pending();
    final rejected = await widget.platform.rejected();
    final notifications = await widget.platform.notificationsAllowed();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _pending = pending;
      _rejected = rejected;
      _notifications = notifications;
    });
  }

  /// Xác thực phụ huynh; ghi vào nhật ký mở khóa kèm [action].
  Future<bool> _authenticate(String action) async {
    final guard = ParentGuardScope.maybeOf(context);
    if (guard == null) return true;
    return guard.require(action, promptPin: ParentGate.promptFor(context));
  }

  Future<void> _toggle(bool on) async {
    final action = on ? 'Bật duyệt app mới' : 'Tắt duyệt app mới';
    if (!await _authenticate(action)) return;
    await widget.platform.setEnabled(on);
    await _load();
  }

  Future<void> _approve(PendingApp app) async {
    if (!await _authenticate('Cho phép app ${app.label}')) return;
    await widget.platform.approve(app.packageName);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Đã cho phép ${app.label}.')));
  }

  Future<void> _reject(PendingApp app) async {
    if (!await _authenticate('Từ chối app ${app.label}')) return;
    await widget.platform.reject(app.packageName);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã từ chối ${app.label}, app vẫn bị chặn.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Duyệt app mới cài')),
      body: enabled == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpace.lg),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Chặn app mới cho tới khi được duyệt'),
                  subtitle: const Text(
                    'App cài sau khi bật bị chặn, phụ huynh xác thực rồi mới '
                    'cho dùng. App đang có sẵn không bị ảnh hưởng.',
                  ),
                  value: enabled,
                  onChanged: _toggle,
                ),
                if (enabled && !_notifications) ...[
                  const SizedBox(height: AppSpace.md),
                  StatusBanner(
                    type: StatusType.warning,
                    title: 'Chưa có thông báo',
                    message:
                        'Cho phép thông báo để biết ngay khi con cài app mới. '
                        'Nếu không, app vẫn bị chặn nhưng bạn chỉ thấy ở đây.',
                    actions: [
                      TextButton(
                        onPressed: () async {
                          await widget.platform.requestNotifications();
                          await _load();
                        },
                        child: const Text('Cho phép thông báo'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpace.lg),
                if (!enabled)
                  const Text('Tính năng đang tắt.')
                else if (_pending.isEmpty)
                  const StatusBanner(
                    type: StatusType.success,
                    title: 'Không có app nào chờ duyệt',
                  )
                else ...[
                  Text(
                    'Đang chờ duyệt (${_pending.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  for (final app in _pending)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.new_releases_outlined),
                                const SizedBox(width: AppSpace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        app.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        app.packageName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
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
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _reject(app),
                                    child: const Text('Từ chối'),
                                  ),
                                ),
                                const SizedBox(width: AppSpace.sm),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => _approve(app),
                                    child: const Text('Cho phép'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (enabled && _rejected.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    'Đã từ chối (${_rejected.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  for (final app in _rejected)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.block),
                        title: Text(app.label),
                        subtitle: Text(app.packageName),
                        trailing: TextButton(
                          onPressed: () => _approve(app),
                          child: const Text('Cho phép'),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
