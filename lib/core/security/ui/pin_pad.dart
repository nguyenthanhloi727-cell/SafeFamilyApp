import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// C18 — Bàn phím PIN: chấm hiển thị số đã nhập + phím 0–9, xóa, xác nhận.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onSubmit,
    this.enabled = true,
    this.minLength = 4,
    this.maxLength = 6,
  });

  final ValueChanged<String> onSubmit;
  final bool enabled;
  final int minLength;
  final int maxLength;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _type(String digit) {
    if (!widget.enabled || _pin.length >= widget.maxLength) return;
    setState(() => _pin += digit);
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    if (_pin.length < widget.minLength) return;
    final pin = _pin;
    setState(() => _pin = '');
    widget.onSubmit(pin);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const key = 72.0;

    Widget digitKey(String digit) => SizedBox.square(
      dimension: key,
      child: Semantics(
        button: true,
        label: 'Số $digit',
        excludeSemantics: true,
        child: Material(
          color: scheme.surfaceContainerLowest,
          shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.enabled ? () => _type(digit) : null,
            child: Center(
              child: Text(
                digit,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: widget.enabled ? null : scheme.outline),
              ),
            ),
          ),
        ),
      ),
    );

    Widget row(List<Widget> keys) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: keys,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Đã nhập ${_pin.length} số',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.maxLength; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  width: AppSpace.lg,
                  height: AppSpace.lg,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? scheme.primary : null,
                    border: Border.all(
                      color: i < widget.minLength
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        row([digitKey('1'), digitKey('2'), digitKey('3')]),
        row([digitKey('4'), digitKey('5'), digitKey('6')]),
        row([digitKey('7'), digitKey('8'), digitKey('9')]),
        row([
          SizedBox.square(
            dimension: key,
            child: IconButton(
              tooltip: 'Xóa số',
              onPressed: widget.enabled && _pin.isNotEmpty ? _backspace : null,
              icon: const Icon(Icons.backspace_outlined),
            ),
          ),
          digitKey('0'),
          SizedBox.square(
            dimension: key,
            child: IconButton.filled(
              tooltip: 'Xác nhận',
              onPressed: widget.enabled && _pin.length >= widget.minLength
                  ? _submit
                  : null,
              icon: const Icon(Icons.check_rounded),
            ),
          ),
        ]),
      ],
    );
  }
}
