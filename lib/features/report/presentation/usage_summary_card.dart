import 'package:flutter/material.dart';

import '../../../core/widgets/feature_card.dart';
import '../../time_limit/data/time_limit_platform.dart';
import '../domain/usage_report.dart';

/// Thẻ Trang chủ "Thời gian dùng máy": "Hôm nay con dùng 1 giờ 20 phút, còn 40 phút".
/// Chưa có quyền đo hoặc không đọc được thì hiện mô tả chung.
class UsageSummaryCard extends StatefulWidget {
  const UsageSummaryCard({
    super.key,
    required this.onTap,
    this.platform = const MethodChannelTimeLimit(),
  });

  final VoidCallback onTap;
  final TimeLimitPlatform platform;

  @override
  State<UsageSummaryCard> createState() => _UsageSummaryCardState();
}

class _UsageSummaryCardState extends State<UsageSummaryCard>
    with WidgetsBindingObserver {
  static const _fallback = 'Thống kê thời gian con dùng điện thoại mỗi ngày';

  String _subtitle = _fallback;

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
    String text;
    try {
      final days = await widget.platform.usageReport(1);
      if (days == null || days.isEmpty) {
        text = _fallback;
      } else {
        final config = await widget.platform.load();
        final bonus = await widget.platform.bonusMinutes();
        text = todaySummary(
          days.last.totalMinutes,
          limitMinutes: totalLimitFor(config, days.last.date),
          bonusMinutes: bonus,
        );
      }
    } on Object {
      text = _fallback;
    }
    if (mounted && text != _subtitle) setState(() => _subtitle = text);
  }

  @override
  Widget build(BuildContext context) => FeatureCard(
    icon: Icons.hourglass_bottom_rounded,
    title: 'Thời gian dùng máy',
    subtitle: _subtitle,
    onTap: widget.onTap,
  );
}
