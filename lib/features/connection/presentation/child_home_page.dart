import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_shell.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../app_lock/presentation/app_lock_controller.dart';
import '../../time_limit/data/time_limit_platform.dart';
import '../../time_limit/domain/time_limit_config.dart';

/// Màn chính của MÁY CON (đã ghép đôi): chỉ cho con xem mình đang bị chặn gì và
/// còn bao nhiêu thời gian. Không có nút chỉnh gì; vào app đầy đủ phải qua
/// "Dành cho phụ huynh" (vân tay / PIN).
class ChildHomePage extends StatefulWidget {
  const ChildHomePage({
    super.key,
    this.platform = const MethodChannelTimeLimit(),
    this.refreshEvery = const Duration(seconds: 30),
  });

  final TimeLimitPlatform platform;
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
    });
    if (_me == null) unawaited(_loadMe());
  }

  String _name(String package) => _labels[package] ?? package;

  Future<void> _openParentArea() async {
    if (!await ParentGate.always(context, 'Mở khu vực phụ huynh')) return;
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AppShell()));
    if (mounted) unawaited(_reload());
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
        onRefresh: _reload,
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
            const SizedBox(height: AppSpace.lg),
            ..._statusCards(theme),
            Text('Ứng dụng đang bị chặn', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
            if (blocked.isEmpty)
              const Text('Hiện chưa có ứng dụng nào bị chặn.')
            else
              for (final package in blocked)
                _blockedTile(theme, controller!, package),
            const SizedBox(height: AppSpace.xl),
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

/// "1 giờ 5 phút", "45 phút".
String _minutes(int m) {
  if (m < 60) return '$m phút';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h giờ' : '$h giờ $r phút';
}
