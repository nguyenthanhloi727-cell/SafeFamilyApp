import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/remote_commands.dart';
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
  /// Chế độ mẹ hỏi lại trạng thái máy con mỗi chừng này khi thẻ đang hiện.
  static const _remoteRefresh = Duration(seconds: 60);

  int _left = 0;

  /// Chế độ mẹ: trạng thái máy con lần tải cuối. `null` = chưa tải được (mất mạng...).
  DeviceStatusInfo? _remote;

  /// Lúc mẹ gửi lệnh gần nhất trong phiên này, để hiện "chờ máy con" tới khi máy con báo lại.
  DateTime? _sentAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_remoteRefresh, (_) => _refreshRemote());
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshRemote();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    await _refreshRemote();
  }

  /// Chế độ mẹ: lấy `isPaused` của máy con. Lỗi thì giữ giá trị cũ, thẻ vẫn dùng được.
  Future<void> _refreshRemote() async {
    final child = RemoteCommands.targetOf(context);
    final api = ApiScope.maybeOf(context);
    if (child == null || api == null) return;
    try {
      final status = await api.getDeviceStatus(child);
      if (mounted) setState(() => _remote = status);
    } on ApiException {
      // Giữ trạng thái cũ.
    }
  }

  /// Trạng thái máy con đã biết chắc (máy con bản mới đã báo ít nhất một lần).
  DeviceStatusInfo? get _knownRemote =>
      (_remote?.hasReported ?? false) ? _remote : null;

  /// Đã gửi lệnh mà máy con chưa báo lại sau đó.
  bool get _waitingChild {
    final sent = _sentAt;
    if (sent == null) return false;
    final reported = _remote?.reportedAt;
    return reported == null || reported.isBefore(sent);
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

  /// Máy mẹ đã chọn máy con. Biết máy con đang tạm dừng thì chạm là xác nhận "tiếp tục";
  /// biết đang chạy thì chỉ hỏi thời lượng tạm dừng. Chưa biết (máy con chưa báo, mất mạng)
  /// thì giữ hộp chọn đủ cả hai, không đoán.
  Future<void> _remoteTap(int child) async {
    final known = _knownRemote;
    if (known != null && known.isPaused) {
      if (!await _authenticate('Tiếp tục dùng máy (hết tạm dừng)')) return;
      if (!mounted) return;
      await _sendRemote(
        child,
        'unpause',
        done: 'Đã gửi lệnh tiếp tục. Máy con nhận ở lần đồng bộ kế.',
      );
      return;
    }
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
          if (known == null)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(-1),
              child: const Text('Tiếp tục dùng máy (hết tạm dừng)'),
            ),
        ],
      ),
    );
    if (minutes == null || !mounted) return;
    if (minutes == -1) {
      if (!await _authenticate('Tiếp tục dùng máy (hết tạm dừng)')) return;
      if (!mounted) return;
      await _sendRemote(
        child,
        'unpause',
        done: 'Đã gửi lệnh tiếp tục. Máy con nhận ở lần đồng bộ kế.',
      );
      return;
    }
    final action = minutes == 0
        ? 'Tạm dừng máy cho tới khi tắt'
        : 'Tạm dừng máy ${formatMinutes(minutes)}';
    if (!await _authenticate(action)) return;
    if (!mounted) return;
    await _sendRemote(
      child,
      'pause',
      payloadJson: RemoteCommands.minutesPayload(minutes),
      done: 'Đã gửi lệnh tạm dừng. Máy con nhận ở lần đồng bộ kế.',
    );
  }

  Future<void> _sendRemote(
    int child,
    String type, {
    String? payloadJson,
    required String done,
  }) async {
    final sent = await RemoteCommands.send(
      context,
      child,
      type,
      payloadJson: payloadJson,
      done: done,
    );
    if (sent && mounted) setState(() => _sentAt = DateTime.now());
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

  String _remoteSubtitle(bool paused) {
    if (_waitingChild) return 'Đã gửi lệnh, chờ máy con xác nhận (tối đa vài phút)';
    if (_knownRemote == null) {
      return 'Gửi lệnh tạm dừng hoặc tiếp tục tới máy con đã chọn';
    }
    return paused
        ? 'Máy con đang tạm dừng — chạm để cho dùng lại'
        : 'Khóa mọi ứng dụng trên máy con, chỉ còn gọi điện';
  }

  @override
  Widget build(BuildContext context) {
    final child = RemoteCommands.targetOf(context);
    if (child != null) {
      final paused = _knownRemote?.isPaused ?? false;
      return FeatureCard(
        icon: paused
            ? Icons.play_circle_outline_rounded
            : Icons.pause_circle_outline_rounded,
        title: paused ? 'Tiếp tục dùng máy con' : 'Tạm dừng máy con',
        subtitle: _remoteSubtitle(paused),
        onTap: () => _remoteTap(child),
      );
    }
    return FeatureCard(
      icon: _left == 0
          ? Icons.pause_circle_outline_rounded
          : Icons.play_circle_outline_rounded,
      title: _left == 0 ? 'Tạm dừng máy' : 'Tiếp tục dùng máy',
      subtitle: _subtitle,
      onTap: _left == 0 ? _pause : _resume,
    );
  }
}
