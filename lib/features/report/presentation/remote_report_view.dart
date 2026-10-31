import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/status_banner.dart';
import '../../time_limit/domain/time_limit_config.dart';
import '../domain/usage_report.dart';

const _remoteDays = 7;

/// Bảy ngày kết thúc ở [today] (cũ nhất trước); ngày máy con chưa báo là 0 phút.
List<DayUsage> remoteWeek(List<UsageDayInfo> reported, DateTime today) {
  final byDate = {
    for (final d in reported) DateTime(d.date.year, d.date.month, d.date.day): d,
  };
  return [
    for (var i = _remoteDays - 1; i >= 0; i--)
      () {
        final day = DateTime(today.year, today.month, today.day - i);
        final r = byDate[day];
        return DayUsage(
          date: day,
          totalMinutes: r?.totalMinutes ?? 0,
          blocks: r?.blocks ?? 0,
          apps: r?.apps ?? const {},
        );
      }(),
  ];
}

/// Phía mẹ: báo cáo thời gian dùng của máy con đọc từ server (API-08). Chỉ phút theo app do máy con báo
/// (mỗi lượt đồng bộ, trễ tối đa vài phút); không có nội dung hay vị trí. Có chọn máy con khi gia đình có nhiều máy.
class RemoteReportView extends StatefulWidget {
  const RemoteReportView({super.key, required this.deviceId, this.now});

  final int deviceId;

  /// Giờ hiện tại (test).
  final DateTime Function()? now;

  @override
  State<RemoteReportView> createState() => _RemoteReportViewState();
}

class _RemoteReportViewState extends State<RemoteReportView> {
  late int _deviceId = widget.deviceId;
  List<DeviceInfo> _devices = const [];
  List<DayUsage>? _days;
  Map<String, String> _labels = const {};
  String? _error;
  int? _selectedDay;
  String? _selectedApp;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = ApiScope.of(context);
    final id = _deviceId;
    try {
      final today = DateTime(_now.year, _now.month, _now.day);
      final reported = await api.getDeviceUsage(
        id,
        from: DateTime(today.year, today.month, today.day - (_remoteDays - 1)),
        to: today,
      );
      var devices = _devices;
      if (devices.isEmpty) {
        try {
          devices = await api.listDevices();
        } on ApiException {
          // Không có danh sách máy: vẫn xem được máy đang chọn.
        }
      }
      // Nhãn app: server chỉ có tên gói; tên đẹp lấy từ danh sách app máy con đã báo (nếu có).
      var labels = const <String, String>{};
      try {
        labels = {
          for (final a in await api.getDeviceApps(id)) a.packageName: a.label,
        };
      } on ApiException {
        // Không có nhãn: hiện tên gói.
      }
      if (!mounted || id != _deviceId) return; // đã đổi sang máy khác
      setState(() {
        _days = remoteWeek(reported, today);
        _devices = devices;
        _labels = labels;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && id == _deviceId) setState(() => _error = e.message);
    }
  }

  void _pick(int id) {
    if (id == _deviceId) return;
    setState(() {
      _deviceId = id;
      _days = null;
      _error = null;
      _selectedDay = null;
      _selectedApp = null;
    });
    _load();
  }

  String _nameOf(String pkg) => _labels[pkg] ?? pkg;

  int _minutesOf(DayUsage d) =>
      _selectedApp == null ? d.totalMinutes : (d.apps[_selectedApp] ?? 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _days;
    final empty = days != null && days.every((d) => d.totalMinutes == 0 && d.blocks == 0 && d.apps.isEmpty);
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo thời gian dùng')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (_devices.length > 1) ...[
              DropdownButton<int>(
                key: const Key('report-device'),
                isExpanded: true,
                value: _devices.any((d) => d.id == _deviceId) ? _deviceId : null,
                items: [
                  for (final d in _devices)
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (id) {
                  if (id != null) _pick(id);
                },
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (_error != null)
              StatusBanner(
                type: StatusType.warning,
                title: 'Không tải được báo cáo',
                message: _error!,
                actions: [
                  FilledButton(onPressed: _load, child: const Text('Thử lại')),
                ],
              )
            else if (days == null)
              const Padding(
                padding: EdgeInsets.all(AppSpace.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (empty)
              const StatusBanner(
                type: StatusType.info,
                title: 'Chưa có số liệu',
                message:
                    'Máy con chưa báo cáo. Máy con cần được cấp quyền "Truy cập '
                    'dữ liệu sử dụng" và báo lên sau mỗi lần đồng bộ (tối đa vài phút).',
              )
            else ...[
              ..._today(theme, days.last),
              const SizedBox(height: AppSpace.xl),
              ..._chart(theme, days),
              const SizedBox(height: AppSpace.xl),
              ..._topApps(theme, days),
              const SizedBox(height: AppSpace.xl),
              ..._weekStats(theme, days),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _today(ThemeData theme, DayUsage today) => [
    Text('Hôm nay', style: theme.textTheme.titleMedium),
    const SizedBox(height: AppSpace.xs),
    Text(
      formatMinutes(today.totalMinutes),
      key: const Key('report-today'),
      style: theme.textTheme.headlineMedium,
    ),
  ];

  List<Widget> _chart(ThemeData theme, List<DayUsage> days) {
    final values = [for (final d in days) _minutesOf(d)];
    final peak = values.fold(0, (a, b) => a > b ? a : b);
    final maxY = ((peak / 60).ceil() * 60).clamp(60, 24 * 60).toDouble();
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
          key: const Key('report-chart'),
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
                      weekdayLabels[days[v.toInt()].date.weekday - 1],
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
            key: Key('top-${app.packageName}'),
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.apps_rounded, size: 18),
            ),
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
    ];
  }
}

/// Nhãn trục ngày (T2 … CN), cùng thứ tự `DateTime.weekday - 1`.
const weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
