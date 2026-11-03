import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_shell.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/connection_session.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/services/external_launcher.dart';
import '../../../core/theme/app_tokens.dart';
import '../../app_lock/presentation/app_lock_controller.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../data/family_platform.dart';
import '../../time_limit/data/time_limit_platform.dart';
import '../../time_limit/domain/time_limit_config.dart';

/// Màn chính của MÁY CON (đã ghép đôi): chỉ cho con xem mình đang bị chặn gì và
/// còn bao nhiêu thời gian. Không có nút chỉnh gì; vào app đầy đủ phải qua
/// "Dành cho phụ huynh" (vân tay / PIN).
class ChildHomePage extends StatefulWidget {
  const ChildHomePage({
    super.key,
    this.platform = const MethodChannelTimeLimit(),
    this.family = const MethodChannelFamily(),
    this.launcher = const UrlExternalLauncher(),
    this.refreshEvery = const Duration(seconds: 30),
  });

  final TimeLimitPlatform platform;
  final FamilyPlatform family;

  /// Mở app Điện thoại để gọi người nhà.
  final ExternalLauncher launcher;
  final Duration refreshEvery;

  @override
  State<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends State<ChildHomePage>
    with WidgetsBindingObserver {
  TimeLimitConfig? _config;
  UsageToday? _usage;
  int _bonus = 0;
  int _pauseLeft = 0;
  StudyStatus _study = const StudyStatus();
  Map<String, String> _labels = const {};
  DeviceSelfInfo? _me;
  Map<String, String> _requests = const {};
  DateTime? _lastSync;
  List<ChildContact> _contacts = const [];
  bool _lastSyncFailed = false;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.refreshEvery, (_) => _reload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reload();
    _loadMe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _loadMe() async {
    final api = ApiScope.maybeOf(context);
    if (api == null) return;
    try {
      final me = await api.fetchMyInfo();
      if (mounted) setState(() => _me = me);
    } on ApiException {
      // Mất mạng: giữ dòng mặc định, lần làm mới sau thử lại.
    }
  }

  Future<void> _reload() async {
    final p = widget.platform;
    final controller = AppLockScope.maybeOf(context);
    await controller?.refresh();
    final config = await p.load();
    final usage = await p.usageToday();
    final bonus = await p.bonusMinutes();
    final pause = await p.pauseMinutesLeft();
    final study = await p.studyStatus();
    final requests = await widget.family.requestStatuses();
    final lastSync = await widget.family.lastSyncAt();
    final contacts = await widget.family.contacts();
    final packages = {
      ...?controller?.lockedPackages,
      ...config.apps.keys,
      ...?usage?.apps.keys,
    }.toList();
    final labels = packages.isEmpty
        ? <String, String>{}
        : await p.appLabels(packages);
    if (!mounted) return;
    setState(() {
      _config = config;
      _usage = usage;
      _bonus = bonus;
      _pauseLeft = pause;
      _study = study;
      _labels = labels;
      _requests = requests;
      _lastSync = lastSync;
      _contacts = contacts;
    });
    if (_me == null) unawaited(_loadMe());
  }

  Future<void> _askExtraTime() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in const [15, 30])
              ListTile(
                key: Key('extra-time-$m'),
                leading: const Icon(Icons.more_time_rounded),
                title: Text('Xin thêm $m phút'),
                onTap: () => Navigator.pop(sheet, m),
              ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    await widget.family.queueRequest('extra_time', minutes: minutes);
    await _reloadRequests();
  }

  Future<void> _studyDone() async {
    await widget.family.queueRequest('study_done');
    await _reloadRequests();
  }

  Future<void> _reloadRequests() async {
    final requests = await widget.family.requestStatuses();
    if (mounted) setState(() => _requests = requests);
  }

  /// Dòng trạng thái yêu cầu cho con; null nếu chưa từng gửi loại này.
  String? _requestText(String kind) => switch (_requests[kind]) {
    'pending' => 'Đã gửi, chờ mẹ duyệt.',
    'approved' => 'Mẹ đã duyệt.',
    'denied' => 'Mẹ từ chối.',
    _ => null,
  };

  List<Widget> _requestButtons() {
    final extraText = _requestText('extra_time');
    final studyText = _requestText('study_done');
    final extraPending = _requests['extra_time'] == 'pending';
    final studyPending = _requests['study_done'] == 'pending';
    return [
      FilledButton.icon(
        key: const Key('child-extra-time'),
        onPressed: extraPending ? null : _askExtraTime,
        icon: const Icon(Icons.more_time_rounded),
        label: const Text('Xin thêm giờ'),
      ),
      if (extraText != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text(extraText, key: const Key('child-extra-time-status')),
        ),
      if (_study.active) ...[
        const SizedBox(height: AppSpace.sm),
        FilledButton.tonalIcon(
          key: const Key('child-study-done'),
          onPressed: studyPending ? null : _studyDone,
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('Con học xong rồi'),
        ),
      ],
      if (studyText != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text(studyText, key: const Key('child-study-done-status')),
        ),
      const SizedBox(height: AppSpace.lg),
    ];
  }

  /// Số SOS đứng trước, rồi tới người nhà khác theo thứ tự mẹ đặt.
  List<ChildContact> get _callList => [
    ..._contacts.where((c) => c.sos),
    ..._contacts.where((c) => !c.sos),
  ];

  Future<void> _call(ChildContact contact) async {
    final ok = await widget.launcher.openDialer(contact.phone);
    if (!ok && mounted) {
      showAppSnackBar(context, 'Không mở được app Điện thoại.');
    }
  }

  List<Widget> _callButtons(ThemeData theme) {
    final list = _callList;
    if (list.isEmpty) return const [];
    return [
      Text('Gọi người nhà', style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpace.sm),
      for (final (i, c) in list.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: c.sos
              ? FilledButton.icon(
                  key: Key('child-call-$i'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => _call(c),
                  icon: const Icon(Icons.sos_rounded),
                  label: Text('SOS: gọi ${c.label}'),
                )
              : FilledButton.tonalIcon(
                  key: Key('child-call-$i'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => _call(c),
                  icon: const Icon(Icons.call_rounded),
                  label: Text('Gọi ${c.label}'),
                ),
        ),
      const SizedBox(height: AppSpace.lg),
    ];
  }

  bool _syncing = false;

  /// Gửi ngay danh sách app, trạng thái, vị trí… lên server và kéo luật mới của mẹ về.
  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final ok = await widget.family.syncNow();
    await _reload();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastSyncFailed = !ok;
    });
    showAppSnackBar(
      context,
      ok
          ? 'Đã đồng bộ với máy mẹ.'
          : 'Chưa đồng bộ được. Kiểm tra mạng rồi thử lại.',
    );
  }

  /// Máy con hỏi máy mẹ ~5 phút một lần; quá ngưỡng này coi là mất kết nối.
  static const _staleAfter = Duration(minutes: 30);

  bool get _offline {
    final last = _lastSync;
    return _lastSyncFailed ||
        last == null ||
        DateTime.now().difference(last) > _staleAfter;
  }

  Widget _syncStatus(ThemeData theme) {
    final last = _lastSync;
    final offline = _offline;
    final text = offline
        ? (last == null
              ? 'Chưa kết nối được máy mẹ.'
              : 'Chưa kết nối được máy mẹ. Đồng bộ lần cuối: ${_ago(DateTime.now().difference(last))}.')
        : 'Đồng bộ lần cuối: ${_ago(DateTime.now().difference(last!))}.';
    return Row(
      children: [
        Icon(
          offline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
          size: 18,
          color: offline ? theme.colorScheme.error : null,
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(
            text,
            key: const Key('child-sync-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: offline ? theme.colorScheme.error : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _transparencyCard(ThemeData theme) => Card(
    key: const Key('child-transparency'),
    child: ListTile(
      leading: const Icon(Icons.visibility_rounded),
      title: const Text('Mẹ xem được gì?'),
      subtitle: const Text(
        'Mẹ xem được: vị trí, thời gian dùng, danh sách app đã cài. '
        'Mẹ không xem nội dung tin nhắn hay trình duyệt.',
      ),
    ),
  );

  String _name(String package) => _labels[package] ?? package;

  Future<void> _openParentArea() async {
    if (!await ParentGate.always(context, 'Mở khu vực phụ huynh')) return;
    if (!mounted) return;
    final choice = await showModalBottomSheet<_ParentChoice>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('parent-open-app'),
              leading: const Icon(Icons.apps_rounded),
              title: const Text('Mở ứng dụng đầy đủ'),
              onTap: () => Navigator.pop(sheet, _ParentChoice.openApp),
            ),
            ListTile(
              key: const Key('parent-disconnect'),
              leading: const Icon(Icons.link_off_rounded),
              title: const Text('Ngắt kết nối với máy mẹ'),
              onTap: () => Navigator.pop(sheet, _ParentChoice.disconnect),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _ParentChoice.openApp:
        await Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const AppShell()));
        if (mounted) unawaited(_reload());
      case _ParentChoice.disconnect:
        // Đã qua khóa phụ huynh ở trên; reset đưa app về màn chọn vai trò.
        await ConnectionScope.of(context).reset();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppLockScope.maybeOf(context);
    final blocked = [
      ...?controller?.lockedPackages,
    ]..sort((a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()));
    return Scaffold(
      appBar: AppBar(title: const Text('SafeFamily')),
      body: RefreshIndicator(
        onRefresh: _syncNow,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Text('Xin chào!', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpace.xs),
            Text(
              _me == null
                  ? 'Máy này đang được gia đình giám sát.'
                  : 'Máy này đang được gia đình "${_me!.familyName}" giám sát.',
            ),
            const SizedBox(height: AppSpace.sm),
            _syncStatus(theme),
            const SizedBox(height: AppSpace.lg),
            ..._callButtons(theme),
            ..._statusCards(theme),
            ..._requestButtons(),
            Text('Ứng dụng đang bị chặn', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
            if (blocked.isEmpty)
              const Text('Hiện chưa có ứng dụng nào bị chặn.')
            else
              for (final package in blocked)
                _blockedTile(theme, controller!, package),
            const SizedBox(height: AppSpace.xl),
            FilledButton.tonalIcon(
              key: const Key('child-sync'),
              onPressed: _syncing ? null : _syncNow,
              icon: const Icon(Icons.sync_rounded),
              label: Text(_syncing ? 'Đang gửi…' : 'Đồng bộ với máy mẹ'),
            ),
            const SizedBox(height: AppSpace.lg),
            _transparencyCard(theme),
            const SizedBox(height: AppSpace.md),
            OutlinedButton.icon(
              key: const Key('child-parent-area'),
              onPressed: _openParentArea,
              icon: const Icon(Icons.lock_person_rounded),
              label: const Text('Dành cho phụ huynh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockedTile(
    ThemeData theme,
    AppLockController controller,
    String package,
  ) {
    final until = controller.unlockedUntil(package);
    final left = until?.difference(DateTime.now());
    return ListTile(
      key: Key('child-blocked-$package'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        left != null && !left.isNegative
            ? Icons.lock_open_rounded
            : Icons.block_rounded,
        color: left != null && !left.isNegative
            ? null
            : theme.colorScheme.error,
      ),
      title: Text(_name(package)),
      subtitle: left != null && !left.isNegative
          ? Text('Đang được mở tạm, còn ${_minutes(left.inMinutes + 1)}')
          : const Text('Đang bị chặn'),
    );
  }

  List<Widget> _statusCards(ThemeData theme) {
    final config = _config;
    if (config == null) return const [];
    final now = DateTime.now();
    final cards = <Widget>[];
    if (_pauseLeft > 0) {
      cards.add(
        _card(
          Icons.pause_circle_rounded,
          'Máy đang tạm dừng',
          _pauseLeft == pauseUntilOff
              ? 'Cho tới khi phụ huynh mở lại.'
              : 'Còn ${_minutes(_pauseLeft)}.',
        ),
      );
    }
    if (_study.active) {
      cards.add(
        _card(
          Icons.school_rounded,
          'Đang trong giờ học',
          _study.sessionMinutesLeft > 0
              ? 'Còn ${_minutes(_study.sessionMinutesLeft)}. Chỉ mở được app học tập.'
              : 'Chỉ mở được app học tập.',
        ),
      );
    }
    if (config.inBedtime(now)) {
      final w = config.bedtime[now.weekday - 1];
      cards.add(
        _card(
          Icons.bedtime_rounded,
          'Đang trong giờ ngủ',
          w == null
              ? 'Nghỉ ngơi thôi con.'
              : 'Tới ${formatClock(w.endMinute)}.',
        ),
      );
    }
    final limit = config.enabled ? config.totalFor(now.weekday) : null;
    final used = _usage?.totalMinutes;
    if (limit != null && used != null) {
      final left = limit + _bonus - used;
      cards.add(
        _card(
          Icons.timer_rounded,
          left > 0
              ? 'Hôm nay còn ${_minutes(left)}'
              : 'Hôm nay đã hết giờ dùng máy',
          'Đã dùng ${_minutes(used)} / ${_minutes(limit + _bonus)}.',
        ),
      );
    } else if (_usage != null) {
      cards.add(
        _card(
          Icons.timer_outlined,
          'Hôm nay đã dùng ${_minutes(_usage!.totalMinutes)}',
          'Hôm nay không giới hạn tổng thời gian.',
        ),
      );
    }
    if (config.enabled) {
      for (final entry in config.apps.entries) {
        final appLimit = config.appLimitFor(entry.key, now.weekday);
        if (appLimit == null) continue;
        final appUsed = _usage?.apps[entry.key] ?? 0;
        final left = appLimit - appUsed;
        cards.add(
          _card(
            Icons.apps_rounded,
            '${_name(entry.key)}: ${left > 0 ? 'còn ${_minutes(left)}' : 'đã hết giờ'}',
            'Đã dùng ${_minutes(appUsed)} / ${_minutes(appLimit)} hôm nay.',
          ),
        );
      }
    }
    return [
      ...cards,
      if (cards.isNotEmpty) const SizedBox(height: AppSpace.lg),
    ];
  }

  Widget _card(IconData icon, String title, String subtitle) => Card(
    margin: const EdgeInsets.only(bottom: AppSpace.sm),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
    ),
  );
}

enum _ParentChoice { openApp, disconnect }

/// "vừa xong", "3 phút trước", "2 giờ trước", "3 ngày trước".
String _ago(Duration d) {
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inHours < 1) return '${d.inMinutes} phút trước';
  if (d.inDays < 1) return '${d.inHours} giờ trước';
  return '${d.inDays} ngày trước';
}

/// "1 giờ 5 phút", "45 phút".
String _minutes(int m) {
  if (m < 60) return '$m phút';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h giờ' : '$h giờ $r phút';
}
