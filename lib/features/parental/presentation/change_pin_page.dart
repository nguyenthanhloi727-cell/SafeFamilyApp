import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/theme/app_tokens.dart';
import 'pin_setup_view.dart';

/// Đổi mã PIN (đã xác thực trước khi mở màn này).
class ChangePinPage extends StatelessWidget {
  const ChangePinPage({super.key, required this.guard});

  final ParentGuard guard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đổi mã PIN')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            PinSetupView(
              onCompleted: (pin) async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                await guard.changePin(pin);
                navigator.pop();
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Đã đổi mã PIN.')),
                  );
              },
            ),
          ],
        ),
      ),
    );
  }
}
