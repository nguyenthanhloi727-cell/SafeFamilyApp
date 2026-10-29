import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../time_limit/data/time_limit_platform.dart';
import '../../time_limit/domain/time_limit_config.dart';
import '../../time_limit/presentation/time_limit_page.dart';

const _shortDays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// "T2–T6 21:00–06:00 · T7, CN 22:00–07:00": gom các ngày liền nhau có cùng
/// khung giờ; không có ngày nào bật thì trả về chuỗi rỗng.
String summarizeWeek(List<BedtimeWindow?> week) {
  final parts = <String>[];
  var i = 0;
  while (i < 7) {
    final window = week[i];
    if (window == null) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < 7 && week[j + 1] == window) {
      j++;
    }
    final days = i == j
        ? _shortDays[i]
        : j == i + 1
        ? '${_shortDays[i]}, ${_shortDays[j]}'
        : '${_shortDays[i]}–${_shortDays[j]}';
    parts.add(
      '$days ${formatClock(window.startMinute)}–${formatClock(window.endMinute)}',
    );
    i = j + 1;
  }
  return parts.join(' · ');
}

/// Phần "Chặn theo giờ" của màn Ứng dụng bị chặn: giờ ngủ, giờ học, hạn mức
/// dùng máy hôm nay và tạm dừng máy. Chỉ hiển thị; bấm vào để sửa ở màn
/// Giới hạn thời gian.
class BlockSchedules extends StatefulWidget {
  const BlockSchedules({
    super.key,
    this.platform = const MethodChannelTimeLimit(),
    this.clock,
  });

  final TimeLimitPlatform platform;
  final DateTime Function()? clock;

  @override
  State<BlockSchedules> createState() => _BlockSchedulesState();
}

class _BlockSchedulesState extends State<BlockSchedules>
    with WidgetsBindingObserver {
  TimeLimitConfig? _config;
  StudyStatus _study = const StudyStatus();
  int _pauseLeft = 0;
  UsageToday? _usage;
  Map<String, String> _labels = const {};

  DateTime get _now => (widget.clock ?? DateTime.now)();

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
    final config = await widget.platform.load();
    final study = await widget.platform.studyStatus();
    final pause = await widget.platform.pauseMinutesLeft();
    final access = await widget.platform.hasUsageAccess();
    final usage = access ? await widget.platform.usageToday() : null;
    final labels = config.apps.isEmpty
        ? const <String, String>{}
        : await widget.platform.appLabels(config.apps.keys.toList());
    if (!mounted) return;
    setState(() {
      _config = config;
      _study = study;
      _pauseLeft = pause;
      _usage = usage;
      _labels = labels;
    });
  }

  Future<void> _openTimeLimits() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const TimeLimitPage()));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chặn theo giờ', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpace.xs),
        Text(
          'App bị khóa tự động theo lịch bạn đặt. Bấm vào để chỉnh.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        if (config == null)
          const Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_pauseLeft > 0)
            _ScheduleCard(
              icon: Icons.pause_circle_outline_rounded,
              title: 'Tạm dừng máy',
              detail: _pauseLeft == pauseUntilOff
                  ? 'Khóa mọi ứng dụng cho tới khi bạn tắt'
                  : 'Khóa mọi ứng dụng, còn ${formatMinutes(_pauseLeft)}',
              active: true,
              onTap: _openTimeLimits,
            ),
          _bedtimeCard(config),
          _studyCard(config),
          _limitCard(config),
        ],
      ],
    );
  }

  Widget _bedtimeCard(TimeLimitConfig config) {
    final summary = summarizeWeek(config.bedtime);
    final on = config.bedtimeEnabled && summary.isNotEmpty;
    return _ScheduleCard(
      icon: Icons.bedtime_outlined,
      title: 'Giờ ngủ',
      detail: on ? summary : 'Chưa đặt',
      status: on && config.inBedtime(_now) ? 'Đang chặn lúc này' : null,
      active: on && config.inBedtime(_now),
      onTap: _openTimeLimits,
    );
  }

  Widget _studyCard(TimeLimitConfig config) {
    final summary = summarizeWeek(config.study);
    final on = config.studyEnabled && summary.isNotEmpty;
    final String detail;
    if (!on) {
      detail = 'Chưa đặt';
    } else {
      final allowed = config.studyApps.length;
      detail =
          '$summary\nChỉ mở được gọi điện, máy tính, từ điển'
          '${allowed == 0 ? '' : ' và $allowed app bạn chọn'}';
    }
    final String? status;
    if (_study.sessionMinutesLeft > 0) {
      status = 'Đang học, còn ${formatMinutes(_study.sessionMinutesLeft)}';
    } else if (_study.disabledToday && on) {
      status = 'Đã tắt đến hết hôm nay';
    } else if (on && _study.active) {
      status = 'Đang chặn lúc này';
    } else {
      status = null;
    }
    return _ScheduleCard(
      icon: Icons.school_outlined,
      title: 'Giờ học',
      detail: detail,
      status: status,
      active: _study.sessionMinutesLeft > 0 || (on && _study.active),
      onTap: _openTimeLimits,
    );
  }

  Widget _limitCard(TimeLimitConfig config) {
    if (!config.enabled) {
      return _ScheduleCard(
        icon: Icons.hourglass_bottom_rounded,
        title: 'Hạn mức dùng máy',
        detail: 'Chưa bật',
        onTap: _openTimeLimits,
      );
    }
    final weekday = _now.weekday;
    final lines = <String>[];
    final total = config.totalFor(weekday);
    var blocked = false;
    if (total != null) {
      final used = _usage?.totalMinutes;
      lines.add(
        used == null
            ? 'Tổng hôm nay: ${formatMinutes(total)}'
            : 'Tổng hôm nay: ${formatMinutes(used)} / ${formatMinutes(total)}',
      );
      if (used != null && used >= total) blocked = true;
    }
    final apps = config.apps.keys.toList()
      ..sort((a, b) => _name(a).compareTo(_name(b)));
    for (final package in apps) {
      final limit = config.appLimitFor(package, weekday);
      if (limit == null) continue;
      final used = _usage?.apps[package];
      final over = used != null && used >= limit;
      if (over) blocked = true;
      lines.add(
        '${_name(package)}: '
        '${used == null ? '' : '${formatMinutes(used)} / '}'
        '${formatMinutes(limit)}${over ? ' · hết giờ, đang chặn' : ''}',
      );
    }
    return _ScheduleCard(
      icon: Icons.hourglass_bottom_rounded,
      title: 'Hạn mức dùng máy',
      detail: lines.isEmpty ? 'Hôm nay không giới hạn' : lines.join('\n'),
      status: blocked ? 'Có app đã hết giờ' : null,
      active: blocked,
      onTap: _openTimeLimits,
    );
  }

  String _name(String package) => _labels[package] ?? package;
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.status,
    this.active = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? status;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: ListTile(
        leading: Icon(icon, color: active ? scheme.error : scheme.primary),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  status!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: active ? scheme.error : scheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
