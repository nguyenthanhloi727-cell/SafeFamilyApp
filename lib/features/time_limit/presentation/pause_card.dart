import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/widgets/feature_card.dart';
import '../data/time_limit_platform.dart';
import '../domain/time_limit_config.dart';

/// Thời lượng chọn khi tạm dừng máy (phút); 0 = đến khi phụ huynh tắt.
const pauseChoices = [15, 30, 60, 0];

String pauseChoiceLabel(int minutes) =>
    minutes == 0 ? 'Cho tới khi tắt' : formatMinutes(minutes);

/// Thẻ Trang chủ "Tạm dừng máy": khóa toàn bộ trừ gọi điện ngay lập tức.
/// Bật và tắt đều qua xác thực phụ huynh (vân tay hoặc PIN) và ghi nhật ký.
class PauseCard extends StatefulWidget {
  const PauseCard({
    super.key,
    this.platform = const MethodChannelTimeLimit(),
    this.guard,
  });

  final TimeLimitPlatform platform;

  /// `null` lấy từ [ParentGuardScope]; không có thì bỏ qua xác thực (test).
  final ParentGuard? guard;

  @override
  State<PauseCard> createState() => _PauseCardState();
}

class _PauseCardState extends State<PauseCard> with WidgetsBindingObserver {
  int _left = 0;

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
    final left = await widget.platform.pauseMinutesLeft();
    if (mounted && left != _left) setState(() => _left = left);
  }

  Future<bool> _authenticate(String action) async {
    final guard = widget.guard ?? ParentGuardScope.maybeOf(context);
    if (guard == null) return true;
    return guard.require(action, promptPin: ParentGate.promptFor(context));
  }

  Future<void> _pause() async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tạm dừng máy của con'),
        children: [
          for (final m in pauseChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: Text(pauseChoiceLabel(m)),
            ),
        ],
      ),
    );
    if (minutes == null || !mounted) return;
    final action = minutes == 0
        ? 'Tạm dừng máy cho tới khi tắt'
        : 'Tạm dừng máy ${formatMinutes(minutes)}';
    if (!await _authenticate(action)) return;
    await widget.platform.startPause(minutes);
    await _refresh();
  }

  Future<void> _resume() async {
    if (!await _authenticate('Tiếp tục dùng máy (hết tạm dừng)')) return;
    await widget.platform.stopPause();
    await _refresh();
  }

  String get _subtitle {
    if (_left == 0) {
      return 'Khóa mọi ứng dụng ngay, chỉ còn gọi điện';
    }
    if (_left == pauseUntilOff) {
      return 'Đang tạm dừng cho tới khi phụ huynh tắt — chạm để tiếp tục';
    }
    return 'Đang tạm dừng, còn ${formatMinutes(_left)} — chạm để tiếp tục';
  }

  @override
  Widget build(BuildContext context) => FeatureCard(
    icon: _left == 0
        ? Icons.pause_circle_outline_rounded
        : Icons.play_circle_outline_rounded,
    title: _left == 0 ? 'Tạm dừng máy' : 'Tiếp tục dùng máy',
    subtitle: _subtitle,
    onTap: _left == 0 ? _pause : _resume,
  );
}
