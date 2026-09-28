import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/status_banner.dart';
import '../lockout_policy.dart';
import '../parent_guard.dart';
import 'forgot_pin_dialog.dart';
import 'pin_pad.dart';

/// S16 — Nhập mã PIN phụ huynh. Trả về `true` khi đúng, `false` khi đóng.
class PinPromptPage extends StatefulWidget {
  const PinPromptPage({super.key, required this.session});

  final PinPromptSession session;

  @override
  State<PinPromptPage> createState() => _PinPromptPageState();
}

class _PinPromptPageState extends State<PinPromptPage> {
  String? _error;
  bool _checking = false;
  Timer? _ticker;
  int _padKey = 0;

  DateTime? get _lockedUntil => widget.session.lockedUntil();

  @override
  void initState() {
    super.initState();
    _startTickerIfLocked();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTickerIfLocked() {
    _ticker?.cancel();
    if (_lockedUntil == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {});
      if (_lockedUntil == null) {
        timer.cancel();
        _error = null;
      }
    });
  }

  Future<void> _submit(String pin) async {
    setState(() => _checking = true);
    final result = await widget.session.check(pin);
    if (!mounted) return;
    switch (result) {
      case PinAccepted():
        Navigator.of(context).pop(true);
        return;
      case PinRejected(:final attemptsLeft):
        _error =
            'Sai mã PIN. Còn $attemptsLeft lần thử trước khi bị khóa tạm thời.';
      case PinLocked():
        _error = 'Nhập sai quá nhiều lần.';
        _startTickerIfLocked();
    }
    setState(() {
      _checking = false;
      _padKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = _lockedUntil;
    final remaining = locked?.difference(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Hủy',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Xác thực phụ huynh'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: AppSize.avatarMd,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Nhập mã PIN phụ huynh',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            Text(
              'để: ${widget.session.action}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.session.notice case final notice?) ...[
              const SizedBox(height: AppSpace.md),
              StatusBanner(type: StatusType.warning, title: notice),
            ],
            const SizedBox(height: AppSpace.md),
            SizedBox(
              height: AppSpace.xxxl,
              child: Center(
                child: locked != null
                    ? Text(
                        'Tạm khóa — thử lại sau ${_formatRemaining(remaining!)}',
                        key: const Key('pin-locked'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      )
                    : _checking
                    ? const CircularProgressIndicator()
                    : Text(
                        _error ?? 'Mã PIN gồm 4–6 chữ số',
                        key: const Key('pin-message'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _error == null
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                        ),
                      ),
              ),
            ),
            PinPad(
              key: ValueKey(_padKey),
              enabled: locked == null && !_checking,
              onSubmit: _submit,
            ),
            const SizedBox(height: AppSpace.md),
            Center(
              child: TextButton(
                onPressed: () => showForgotPinDialog(context),
                child: const Text('Quên mã PIN?'),
              ),
            ),
            Text(
              'Sai $pinAttemptsBeforeLock lần sẽ bị khóa '
              '${firstLockDuration.inSeconds} giây, sai tiếp khóa lâu hơn.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRemaining(Duration d) {
  final seconds = d.inSeconds < 0 ? 0 : d.inSeconds + 1;
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return m > 0 ? '$m phút ${s.toString().padLeft(2, '0')} giây' : '$s giây';
}
