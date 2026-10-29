import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_banner.dart';
import '../../app_lock/data/app_lock_platform.dart';
import '../data/time_limit_platform.dart';
import '../domain/age_profile.dart';
import '../domain/time_limit_config.dart';
import 'extra_time.dart';

/// Thời lượng chọn cho "Bắt đầu giờ học ngay" (phút).
const studySessionChoices = [30, 60, 90];

/// Giới hạn thời gian dùng máy theo ngày: tổng và từng app, khác nhau theo thứ.
/// Việc đếm giờ và chặn chạy ở native; màn này chỉ cấu hình và hiển thị.
class TimeLimitPage extends StatefulWidget {
  const TimeLimitPage({
    super.key,
    this.platform = const MethodChannelTimeLimit(),
    this.loadApps,
  });

  final TimeLimitPlatform platform;

  /// Danh sách app để chọn thêm giới hạn riêng (mặc định: app_blocker).
  final Future<List<InstalledApp>> Function()? loadApps;

  @override
  State<TimeLimitPage> createState() => _TimeLimitPageState();
}

class _TimeLimitPageState extends State<TimeLimitPage>
    with WidgetsBindingObserver {
  TimeLimitConfig? _config;
  bool _usageAccess = true;
  UsageToday? _usage;
  int _bonus = 0;
  StudyStatus _study = const StudyStatus();
  DateTime? _limitOffUntil;
  List<InstalledApp>? _apps;

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
    if (state == AppLifecycleState.resumed) _refreshUsage();
  }

  Future<void> _load() async {
    final config = await widget.platform.load();
    if (!mounted) return;
    setState(() => _config = config);
    await _refreshUsage();
    final loader = widget.loadApps ?? AppBlockerPlatform().installedApps;
    try {
      final apps = await loader();
      if (mounted) setState(() => _apps = apps);
    } on Object {
      if (mounted) setState(() => _apps = const []);
    }
  }

  Future<void> _refreshUsage() async {
    final access = await widget.platform.hasUsageAccess();
    final usage = access ? await widget.platform.usageToday() : null;
    final bonus = await widget.platform.bonusMinutes();
    final study = await widget.platform.studyStatus();
    final limitOff = await widget.platform.totalLimitDisabledUntil();
    if (!mounted) return;
    setState(() {
      _usageAccess = access;
      _usage = usage;
      _bonus = bonus;
      _study = study;
      _limitOffUntil = limitOff;
    });
  }

  /// Tắt giới hạn tổng đến hết hôm nay: hỏi xác nhận rồi xác thực phụ huynh.
  /// Bật lại sớm thì siết chặt hơn nên không cần xác thực.
  Future<void> _toggleTotalLimitToday() async {
    final disabling = _limitOffUntil == null;
    if (disabling) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tắt giới hạn cả ngày hôm nay?'),
          content: const Text(
            'Hôm nay con không bị chặn vì hết tổng thời gian dùng máy. Giới '
            'hạn riêng từng app vẫn giữ. Sang ngày mới giới hạn tự bật lại.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tắt hôm nay'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _guarded(
      disabling
          ? 'Tắt giới hạn cả ngày hôm nay'
          : 'Bật lại giới hạn thời gian hôm nay',
      () => widget.platform.setTotalLimitDisabledToday(disabling),
      authenticate: disabling,
    );
  }

  Future<void> _addTime() async {
    final added = await grantExtraTime(
      context,
      platform: widget.platform,
      guard: ParentGuardScope.maybeOf(context),
    );
    if (added != null) await _refreshUsage();
  }

  Future<void> _update(TimeLimitConfig config) async {
    setState(() => _config = config);
    try {
      await widget.platform.save(config);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lưu được, thử lại nhé.')),
      );
    }
  }

  /// Áp mẫu theo độ tuổi: ghi đè tổng thời gian và giờ ngủ, nên hỏi lại trước.
  Future<void> _applyProfile(TimeLimitConfig config, AgeProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Áp dụng mẫu ${profile.label}?'),
        content: Text(
          '${profile.summary}.\n\nTổng thời gian và giờ ngủ hiện tại sẽ bị '
          'thay; giới hạn riêng từng app và giờ học được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _update(profile.applyTo(config));
  }

  String _nameOf(String packageName) {
    for (final app in _apps ?? const <InstalledApp>[]) {
      if (app.packageName == packageName) return app.name;
    }
    return packageName;
  }

  Future<InstalledApp?> _pickApp(Set<String> taken) {
    final choices = [
      for (final app in _apps ?? const <InstalledApp>[])
        if (!taken.contains(app.packageName)) app,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return showModalBottomSheet<InstalledApp>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            const ListTile(title: Text('Chọn ứng dụng')),
            if (choices.isEmpty)
              const ListTile(title: Text('Không còn ứng dụng nào để thêm.')),
            for (final app in choices)
              ListTile(
                leading: app.icon == null
                    ? const Icon(Icons.apps_rounded)
                    : Image.memory(app.icon!, width: 36, height: 36),
                title: Text(app.name),
                onTap: () => Navigator.of(context).pop(app),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addApp(TimeLimitConfig config) async {
    final picked = await _pickApp(config.apps.keys.toSet());
    if (picked == null) return;
    await _update(
      config.copyWith(
        apps: {...config.apps, picked.packageName: unlimitedWeek()},
      ),
    );
  }

  Future<void> _addStudyApp(TimeLimitConfig config) async {
    final picked = await _pickApp(config.studyApps);
    if (picked == null) return;
    await _update(
      config.copyWith(studyApps: {...config.studyApps, picked.packageName}),
    );
  }

  /// Xác thực phụ huynh (vân tay hoặc PIN) rồi chạy [run]; ghi nhật ký mở khóa.
  /// [authenticate] = false cho thao tác siết chặt thêm (bắt đầu / bật lại giờ
  /// học): không cần hỏi, chỉ việc làm cho con bị hạn chế nhiều hơn.
  Future<void> _guarded(
    String action,
    Future<void> Function() run, {
    bool authenticate = true,
  }) async {
    final guard = ParentGuardScope.maybeOf(context);
    if (guard != null && authenticate) {
      final ok = await guard.require(
        action,
        promptPin: ParentGate.promptFor(context),
      );
      if (!ok) return;
    }
    await run();
    await _refreshUsage();
  }

  Future<void> _startStudyNow() async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Bắt đầu giờ học ngay'),
        children: [
          for (final m in studySessionChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: Text('$m phút'),
            ),
        ],
      ),
    );
    if (minutes == null) return;
    await _guarded(
      'Bắt đầu giờ học $minutes phút',
      () => widget.platform.startStudy(minutes),
      authenticate: false,
    );
  }

  /// Bật giờ học thì lưu luôn. Tắt thì phải qua khóa phụ huynh; nếu đang có
  /// phiên chạy thì hỏi dừng luôn hay để chạy hết (phiên chỉ dừng qua
  /// `stopStudy`, tắt lịch không đụng tới phiên đang chạy).
  Future<void> _setStudyEnabled(TimeLimitConfig config, bool enabled) async {
    if (enabled) {
      await _update(config.copyWith(studyEnabled: true));
      return;
    }
    await _refreshUsage();
    if (!mounted) return;
    var stopSession = false;
    if (_study.sessionMinutesLeft > 0) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Đang có phiên học'),
          content: Text(
            'Còn ${formatMinutes(_study.sessionMinutesLeft)}. Dừng phiên luôn '
            'hay để chạy hết?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Để chạy hết'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Dừng phiên'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      stopSession = choice;
    }
    await _guarded('Tắt giờ học', () async {
      if (stopSession) await widget.platform.stopStudy();
      await _update(config.copyWith(studyEnabled: false));
    });
  }

  String _studyStatusText() {
    if (_study.sessionMinutesLeft > 0) {
      return 'Đang học theo phiên, còn '
          '${formatMinutes(_study.sessionMinutesLeft)}.';
    }
    if (_study.disabledToday) return 'Đã tắt giờ học đến hết hôm nay.';
    return _study.active
        ? 'Đang trong giờ học theo lịch.'
        : 'Ngoài giờ học. Ứng dụng mở bình thường.';
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final theme = Theme.of(context);
    return ParentAreaGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Giới hạn thời gian')),
        body: config == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpace.lg),
                children: [
                  if (!_usageAccess) ...[
                    StatusBanner(
                      type: StatusType.error,
                      title: 'Chưa cấp quyền đo thời gian dùng',
                      message:
                          'Không có quyền "Truy cập dữ liệu sử dụng" thì giới '
                          'hạn không có tác dụng. Bấm nút, tìm SafeFamily '
                          'trong danh sách rồi bật.',
                      actions: [
                        TextButton(
                          onPressed: widget.platform.openUsageAccess,
                          child: const Text('Cấp quyền'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                  ],
                  Text('Mẫu theo độ tuổi', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    children: [
                      for (final profile in AgeProfile.values)
                        ActionChip(
                          avatar: const Icon(Icons.child_care_rounded),
                          label: Text(profile.label),
                          onPressed: () => _applyProfile(config, profile),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bật giới hạn thời gian'),
                    subtitle: const Text(
                      'Hết giờ, app bị chặn đến hết ngày. Gọi điện không bao '
                      'giờ bị chặn.',
                    ),
                    value: config.enabled,
                    onChanged: (v) => _update(config.copyWith(enabled: v)),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.more_time_rounded),
                    title: const Text('Thêm giờ hôm nay'),
                    subtitle: Text(
                      _bonus == 0
                          ? 'Cộng 5, 15 hoặc 30 phút cho hôm nay. Tự về 0 '
                                'lúc nửa đêm, không đổi giới hạn bên dưới.'
                          : 'Hôm nay đã thêm ${formatMinutes(_bonus)}.',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _addTime,
                      child: const Text('Thêm giờ'),
                    ),
                  ),
                  const Divider(),
                  Text(
                    'Tổng thời gian dùng máy',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (_usage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs),
                      child: Text(
                        'Hôm nay con đã dùng '
                        '${formatMinutes(_usage!.totalMinutes)}.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  if (_limitOffUntil != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs),
                      child: Text(
                        'Đang tắt tới hết hôm nay.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: _toggleTotalLimitToday,
                      child: Text(
                        _limitOffUntil == null
                            ? 'Tắt giới hạn cả ngày hôm nay'
                            : 'Bật lại giới hạn',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  WeekLimitEditor(
                    limits: config.total,
                    onChanged: (v) => _update(config.copyWith(total: v)),
                  ),
                  const Divider(height: AppSpace.xxl),
                  Text(
                    'Theo từng ứng dụng',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  for (final entry in config.apps.entries)
                    ExpansionTile(
                      key: ValueKey(entry.key),
                      tilePadding: EdgeInsets.zero,
                      title: Text(_nameOf(entry.key)),
                      subtitle: _usage?.apps[entry.key] == null
                          ? null
                          : Text(
                              'Hôm nay: '
                              '${formatMinutes(_usage!.apps[entry.key]!)}',
                            ),
                      children: [
                        WeekLimitEditor(
                          limits: entry.value,
                          onChanged: (v) => _update(
                            config.copyWith(
                              apps: {...config.apps, entry.key: v},
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _update(
                              config.copyWith(
                                apps: {...config.apps}..remove(entry.key),
                              ),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Bỏ giới hạn app này'),
                          ),
                        ),
                      ],
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _apps == null ? null : () => _addApp(config),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Thêm ứng dụng'),
                    ),
                  ),
                  const Divider(height: AppSpace.xxl),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Giờ ngủ'),
                    subtitle: const Text(
                      'Trong khung giờ này mọi ứng dụng bị khóa, chỉ còn gọi '
                      'điện. Khung có thể qua nửa đêm, ví dụ 21:00–06:00.',
                    ),
                    value: config.bedtimeEnabled,
                    onChanged: (v) =>
                        _update(config.copyWith(bedtimeEnabled: v)),
                  ),
                  if (config.bedtimeEnabled)
                    BedtimeEditor(
                      week: config.bedtime,
                      onChanged: (v) => _update(config.copyWith(bedtime: v)),
                    ),
                  const Divider(height: AppSpace.xxl),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Giờ học'),
                    subtitle: const Text(
                      'Trong giờ học chỉ ứng dụng trong danh sách bên dưới '
                      '(cùng gọi điện, máy tính, từ điển) mở được. Giờ ngủ '
                      'được ưu tiên hơn giờ học.',
                    ),
                    value: config.studyEnabled,
                    onChanged: (v) => _setStudyEnabled(config, v),
                  ),
                  if (config.studyEnabled) ...[
                    Text(_studyStatusText(), style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      children: [
                        FilledButton.tonal(
                          onPressed: _startStudyNow,
                          child: const Text('Bắt đầu giờ học ngay'),
                        ),
                        if (_study.sessionMinutesLeft > 0)
                          OutlinedButton(
                            onPressed: () => _guarded(
                              'Dừng giờ học',
                              widget.platform.stopStudy,
                            ),
                            child: const Text('Dừng phiên'),
                          ),
                        OutlinedButton(
                          onPressed: () => _guarded(
                            _study.disabledToday
                                ? 'Bật lại giờ học hôm nay'
                                : 'Tắt giờ học hôm nay',
                            () => widget.platform.setStudyDisabledToday(
                              !_study.disabledToday,
                            ),
                            authenticate: !_study.disabledToday,
                          ),
                          child: Text(
                            _study.disabledToday ? 'Bật lại' : 'Tắt hôm nay',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    BedtimeEditor(
                      week: config.study,
                      emptyLabel: 'Không có giờ học',
                      defaultWindow: defaultStudy,
                      onChanged: (v) => _update(config.copyWith(study: v)),
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      'Ứng dụng được mở trong giờ học',
                      style: theme.textTheme.titleSmall,
                    ),
                    Wrap(
                      spacing: AppSpace.sm,
                      children: [
                        for (final pkg in config.studyApps.toList()..sort())
                          InputChip(
                            label: Text(_nameOf(pkg)),
                            onDeleted: () => _update(
                              config.copyWith(
                                studyApps: {...config.studyApps}..remove(pkg),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _apps == null
                            ? null
                            : () => _addStudyApp(config),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Thêm ứng dụng học'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// 7 dòng: công tắc "có giờ ngủ" + hai nút chọn giờ bắt đầu và kết thúc.
/// Dùng chung cho giờ học (đổi [emptyLabel] và [defaultWindow]).
class BedtimeEditor extends StatelessWidget {
  const BedtimeEditor({
    super.key,
    required this.week,
    required this.onChanged,
    this.emptyLabel = 'Không có giờ ngủ',
    this.defaultWindow = defaultBedtime,
  });

  final WeekBedtime week;
  final ValueChanged<WeekBedtime> onChanged;
  final String emptyLabel;
  final BedtimeWindow defaultWindow;

  Future<void> _pick(
    BuildContext context,
    int day,
    BedtimeWindow window, {
    required bool start,
  }) async {
    final current = start ? window.startMinute : window.endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    onChanged(
      [...week]
        ..[day] = start
            ? window.copyWith(startMinute: minute)
            : window.copyWith(endMinute: minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var day = 0; day < 7; day++)
          Row(
            children: [
              SizedBox(width: 88, child: Text(weekdayNames[day])),
              Expanded(
                child: switch (week[day]) {
                  final window? => Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () =>
                            _pick(context, day, window, start: true),
                        child: Text(formatClock(window.startMinute)),
                      ),
                      const Text('–'),
                      TextButton(
                        onPressed: () =>
                            _pick(context, day, window, start: false),
                        child: Text(formatClock(window.endMinute)),
                      ),
                      if (window.overnight)
                        Text(
                          '(sáng hôm sau)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  null => Text(
                    emptyLabel,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                },
              ),
              Switch(
                value: week[day] != null,
                onChanged: (on) =>
                    onChanged([...week]..[day] = on ? defaultWindow : null),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => onChanged(List<BedtimeWindow?>.filled(7, week[0])),
            child: const Text('Chép Thứ Hai cho cả tuần'),
          ),
        ),
      ],
    );
  }
}

/// 7 dòng (Thứ Hai … Chủ Nhật): công tắc "có giới hạn" + thanh trượt phút.
class WeekLimitEditor extends StatelessWidget {
  const WeekLimitEditor({
    super.key,
    required this.limits,
    required this.onChanged,
  });

  final WeekLimits limits;
  final ValueChanged<WeekLimits> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var day = 0; day < 7; day++)
          _DayRow(
            label: weekdayNames[day],
            minutes: limits[day],
            onChanged: (m) => onChanged([...limits]..[day] = m),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => onChanged(List<int?>.filled(7, limits[0])),
            child: const Text('Chép Thứ Hai cho cả tuần'),
          ),
        ),
      ],
    );
  }
}

class _DayRow extends StatefulWidget {
  const _DayRow({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int? minutes;
  final ValueChanged<int?> onChanged;

  @override
  State<_DayRow> createState() => _DayRowState();
}

class _DayRowState extends State<_DayRow> {
  /// Giá trị đang kéo; chỉ lưu khi thả tay để không ghi liên tục.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final minutes = widget.minutes;
    final shown = (_dragging ?? minutes?.toDouble() ?? 0).round();
    return Column(
      children: [
        Row(
          children: [
            SizedBox(width: 88, child: Text(widget.label)),
            Expanded(
              child: Text(
                minutes == null ? 'Không giới hạn' : formatMinutes(shown),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Switch(
              value: minutes != null,
              onChanged: (on) => widget.onChanged(on ? 60 : null),
            ),
          ],
        ),
        if (minutes != null)
          Slider(
            value: shown.clamp(0, maxLimitMinutes).toDouble(),
            max: maxLimitMinutes.toDouble(),
            label: formatMinutes(shown),
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onChanged(v.round());
            },
          ),
      ],
    );
  }
}
