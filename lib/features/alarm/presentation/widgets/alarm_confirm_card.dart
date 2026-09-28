import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/alarm_time.dart';

/// S05b — Giờ đã hiểu (chữ thật to) + "Đặt báo thức" / "Sửa giờ".
class AlarmConfirmCard extends StatelessWidget {
  const AlarmConfirmCard({
    super.key,
    required this.time,
    required this.now,
    required this.onSchedule,
    required this.onEdit,
  });

  final AlarmTime time;
  final DateTime now;
  final VoidCallback onSchedule;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          children: [
            Text('Báo thức lúc', style: theme.textTheme.titleSmall),
            Text(
              time.format(),
              key: const Key('alarm-time'),
              style: theme.textTheme.displayLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              describeWhen(time, now),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSchedule,
                icon: const Icon(Icons.alarm_add_rounded),
                label: const Text('Đặt báo thức'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Sửa giờ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "sáng ngày mai", "tối hôm nay"…
String describeWhen(AlarmTime time, DateTime now) {
  final next = time.nextOccurrence(now);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(next.year, next.month, next.day) == today
      ? 'hôm nay'
      : 'ngày mai';
  final part = switch (time.hour) {
    >= 5 && < 11 => 'sáng',
    >= 11 && < 13 => 'trưa',
    >= 13 && < 18 => 'chiều',
    >= 18 && < 22 => 'tối',
    _ => 'đêm',
  };
  return '$part $day';
}
