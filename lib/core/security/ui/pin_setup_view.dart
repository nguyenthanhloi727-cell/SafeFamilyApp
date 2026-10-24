import 'package:flutter/material.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../core/security/ui/pin_pad.dart';
import '../../../core/theme/app_tokens.dart';

/// S17 — Đặt mã PIN mới: nhập 2 lần cho khớp. Gọi [onCompleted] với PIN hợp lệ.
class PinSetupView extends StatefulWidget {
  const PinSetupView({super.key, required this.onCompleted});

  final ValueChanged<String> onCompleted;

  @override
  State<PinSetupView> createState() => _PinSetupViewState();
}

class _PinSetupViewState extends State<PinSetupView> {
  String? _first;
  String? _error;
  int _padKey = 0;

  void _submit(String pin) {
    setState(() {
      _padKey++;
      final first = _first;
      if (first == null) {
        _error = pinChoiceProblem(pin);
        if (_error == null) _first = pin;
        return;
      }
      if (pin != first) {
        _first = null;
        _error = 'Hai lần nhập không khớp. Hãy đặt lại từ đầu.';
        return;
      }
      _error = null;
      widget.onCompleted(pin);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirming = _first != null;
    return Column(
      children: [
        Text(
          confirming ? 'Nhập lại mã PIN' : 'Đặt mã PIN phụ huynh',
          key: const Key('pin-setup-title'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          _error ??
              (confirming
                  ? 'Nhập lại đúng mã vừa đặt để xác nhận.'
                  : '4–6 chữ số, không dùng dãy dễ đoán như 1234 hay 0000.'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _error == null
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        PinPad(key: ValueKey(_padKey), onSubmit: _submit),
      ],
    );
  }
}
