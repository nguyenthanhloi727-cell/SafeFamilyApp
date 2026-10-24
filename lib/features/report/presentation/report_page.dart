import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/security/unlock_log.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_banner.dart';
import '../../app_lock/data/app_lock_platform.dart';
import '../../time_limit/data/time_limit_platform.dart';
import '../../time_limit/domain/time_limit_config.dart';
import '../domain/usage_report.dart';

const reportDays = 7;

/// Số lần mở khóa trong [days] ngày gần nhất (không tính thao tác hệ thống/hủy).
({int success, int failure}) unlockCounts(
  List<UnlockLogEntry> entries,
  DateTime now, {
  int days = reportDays,
}) {
  final since = DateTime(now.year, now.month, now.day - (days - 1));
  var success = 0;
  var failure = 0;
  for (final e in entries) {
    if (e.time.isBefore(since) || e.method == UnlockMethod.system) continue;
    if (e.result == UnlockResult.success) success++;
    if (e.result == UnlockResult.failure) failure++;
  }
  return (success: success, failure: failure);
}

/// Báo cáo thời gian dùng: hôm nay so với hạn mức, top 5 app, biểu đồ 7 ngày,
/// số lần chạm app bị chặn và số lần mở khóa trong tuần.
class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    this.platform = const MethodChannelTimeLimit(),
    this.loadApps,
    this.now,
  });

  final TimeLimitPlatform platform;

  /// Danh sách app để lấy tên/biểu tượng (mặc định: app_blocker).
  final Future<List<InstalledApp>> Function()? loadApps;

  /// Giờ hiện tại (test).
  final DateTime Function()? now;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> with WidgetsBindingObserver {
  List<DayUsage>? _days;
  bool _loaded = false;
  TimeLimitConfig _config = TimeLimitConfig();
  int _bonus = 0;
  Map<String, InstalledApp> _apps = const {};
  Map<String, String> _labels = const {};
  ({int success, int failure}) _unlocks = (success: 0, failure: 0);
  int? _selectedDay;
  String? _selectedApp;

  DateTime get _now => (widget.now ?? DateTime.now)();

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
    final platform = widget.platform;
    final days = await platform.usageReport(reportDays);
    final config = await platform.load();
    final bonus = await platform.bonusMinutes();
    var apps = const <String, InstalledApp>{};
    try {
      final list =
          await (widget.loadApps ?? AppBlockerPlatform().installedApps)();
      apps = {for (final a in list) a.packageName: a};
    } on Object {
      // Không có danh sách app: dùng nhãn từ hệ thống hoặc tên gói.
    }
    final shown = {for (final d in days ?? const <DayUsage>[]) ...d.apps.keys};
    final labels = await platform.appLabels([
      for (final pkg in shown)
        if (!apps.containsKey(pkg)) pkg,
    ]);
    if (!mounted) return;
    final log = await ParentGuardScope.maybeOf(context)?.log.entries();
    if (!mounted) return;
    setState(() {
      _days = days;
      _loaded = true;
      _config = config;
      _bonus = bonus;
      _apps = apps;
      _labels = labels;
      _unlocks = unlockCounts(log ?? const [], _now);
    });
  }

  String _nameOf(String pkg) => _apps[pkg]?.name ?? _labels[pkg] ?? pkg;

  Widget _icon(String pkg) {
    final icon = _apps[pkg]?.icon;
    return icon == null
        ? const CircleAvatar(
            radius: 16,
            child: Icon(Icons.apps_rounded, size: 18),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              icon,
              width: 32,
              height: 32,
              gaplessPlayback: true,
            ),
          );
  }

  int _minutesOf(DayUsage day) =>
      _selectedApp == null ? day.totalMinutes : (day.apps[_selectedApp] ?? 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _days;
    return ParentAreaGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Báo cáo thời gian dùng')),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : days == null || days.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(AppSpace.lg),
                children: [
                  StatusBanner(
                    type: StatusType.warning,
                    title: 'Chưa có số liệu',
                    message:
                        'Cần cấp quyền "Truy cập dữ liệu sử dụng" cho SafeFamily '
                        'để đo thời gian con dùng máy.',
                    actions: [
                      FilledButton(
                        onPressed: widget.platform.openUsageAccess,
                        child: const Text('Cấp quyền'),
                      ),
                    ],
                  ),
                ],
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  children: [
                    ..._todayCard(theme, days.last),
                    const SizedBox(height: AppSpace.xl),
                    ..._chart(theme, days),
                    const SizedBox(height: AppSpace.xl),
                    ..._topApps(theme, days),
                    const SizedBox(height: AppSpace.xl),
                    ..._weekStats(theme, days),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _todayCard(ThemeData theme, DayUsage today) {
    final limit = totalLimitFor(_config, today.date);
    final allowed = limit == null ? null : limit + _bonus;
    return [
      Text('Hôm nay', style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpace.xs),
      Text(
        formatMinutes(today.totalMinutes),
        style: theme.textTheme.headlineMedium,
      ),
      const SizedBox(height: AppSpace.sm),
      if (allowed != null) ...[
        LinearProgressIndicator(
          value: allowed == 0
              ? 1
              : (today.totalMinutes / allowed).clamp(0.0, 1.0),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          todaySummary(
            today.totalMinutes,
            limitMinutes: limit,
            bonusMinutes: _bonus,
          ),
          style: theme.textTheme.bodyMedium,
        ),
      ] else
        Text(
          'Chưa đặt hạn mức tổng cho hôm nay.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
    ];
  }

  List<Widget> _chart(ThemeData theme, List<DayUsage> days) {
    final values = [for (final d in days) _minutesOf(d)];
    final peak = values.fold(0, (a, b) => a > b ? a : b);
    final maxY = ((peak / 60).ceil() * 60).clamp(60, 24 * 60).toDouble();
    const names = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final scheme = theme.colorScheme;
    return [
      Row(
        children: [
          Expanded(
            child: Text('7 ngày gần nhất', style: theme.textTheme.titleMedium),
          ),
          if (_selectedApp != null)
            TextButton(
              onPressed: () => setState(() => _selectedApp = null),
              child: const Text('Xem tất cả'),
            ),
        ],
      ),
      if (_selectedApp != null)
        Text(_nameOf(_selectedApp!), style: theme.textTheme.bodyMedium),
      const SizedBox(height: AppSpace.sm),
      SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchCallback: (event, response) {
                final index = response?.spot?.touchedBarGroupIndex;
                if (event.isInterestedForInteractions && index != null) {
                  setState(() => _selectedDay = index);
                }
              },
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: 60,
                  getTitlesWidget: (v, meta) =>
                      Text('${v ~/ 60}g', style: theme.textTheme.labelSmall),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, meta) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      names[days[v.toInt()].date.weekday - 1],
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < days.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: values[i].toDouble(),
                      width: 18,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      color: i == days.length - 1
                          ? scheme.primary
                          : scheme.primary.withValues(alpha: 0.5),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      if (_selectedDay != null && _selectedDay! < days.length)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Text(
            '${weekdayNames[days[_selectedDay!].date.weekday - 1]} '
            '${days[_selectedDay!].date.day}/${days[_selectedDay!].date.month}: '
            '${formatMinutes(values[_selectedDay!])}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
    ];
  }

  List<Widget> _topApps(ThemeData theme, List<DayUsage> days) {
    final top = topApps(days);
    return [
      Text('Dùng nhiều nhất trong tuần', style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpace.sm),
      if (top.isEmpty)
        Text('Chưa có dữ liệu.', style: theme.textTheme.bodyMedium)
      else
        for (final app in top)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _icon(app.packageName),
            title: Text(
              _nameOf(app.packageName),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: LinearProgressIndicator(
              value: app.minutes / top.first.minutes,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            trailing: Text(formatMinutes(app.minutes)),
            selected: _selectedApp == app.packageName,
            onTap: () => setState(
              () => _selectedApp = _selectedApp == app.packageName
                  ? null
                  : app.packageName,
            ),
          ),
    ];
  }

  List<Widget> _weekStats(ThemeData theme, List<DayUsage> days) {
    final blocks = days.fold(0, (sum, d) => sum + d.blocks);
    Widget row(IconData icon, String text) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(text),
    );
    return [
      Text('Trong tuần', style: theme.textTheme.titleMedium),
      row(
        Icons.hourglass_bottom_rounded,
        'Tổng: ${formatMinutes(weekTotalMinutes(days))}',
      ),
      row(Icons.block_rounded, 'Con chạm vào app bị chặn $blocks lần'),
      row(
        Icons.lock_open_rounded,
        'Mở khóa phụ huynh: ${_unlocks.success} thành công, '
        '${_unlocks.failure} thất bại',
      ),
    ];
  }
}
