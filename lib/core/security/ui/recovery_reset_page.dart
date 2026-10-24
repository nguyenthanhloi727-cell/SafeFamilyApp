import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/status_banner.dart';
import '../parent_guard.dart';
import '../recovery_code.dart';
import 'pin_setup_view.dart';
import 'secure_screen_scope.dart';

/// Quên PIN: nhập mã khôi phục, rồi đặt PIN mới.
class RecoveryResetPage extends StatefulWidget {
  const RecoveryResetPage({super.key, required this.guard});

  final ParentGuard guard;

  @override
  State<RecoveryResetPage> createState() => _RecoveryResetPageState();
}

class _RecoveryResetPageState extends State<RecoveryResetPage> {
  final _controller = TextEditingController();
  String? _code;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitCode() {
    final value = _controller.text;
    if (!isRecoveryCodeFormatValid(value)) {
      setState(() => _error = 'Mã gồm $recoveryCodeLength chữ và số.');
      return;
    }
    setState(() {
      _code = normalizeRecoveryCode(value);
      _error = null;
    });
  }

  Future<void> _reset(String newPin) async {
    setState(() => _busy = true);
    final result = await widget.guard.resetPinWithRecoveryCode(_code!, newPin);
    if (!mounted) return;
    switch (result) {
      case PinAccepted():
        Navigator.of(context).popUntil((route) => route.isFirst);
        showAppSnackBar(context, 'Đã đặt mã PIN mới.');
      case PinRejected(:final attemptsLeft):
        setState(() {
          _busy = false;
          _code = null;
          _error =
              'Mã khôi phục không đúng. Còn $attemptsLeft lần thử trước khi '
              'bị khóa tạm thời.';
        });
      case PinLocked():
        setState(() {
          _busy = false;
          _code = null;
          _error = 'Nhập sai quá nhiều lần, hãy thử lại sau ít phút.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SecureScreenScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('Đặt lại PIN bằng mã khôi phục')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else if (_code == null) ...[
                Text('Nhập mã khôi phục', style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpace.sm),
                const Text(
                  'Mã $recoveryCodeLength ký tự phụ huynh đã ghi lại lúc '
                  'thiết lập. Không phân biệt chữ hoa, chữ thường.',
                ),
                const SizedBox(height: AppSpace.md),
                TextField(
                  key: const Key('recovery-input'),
                  controller: _controller,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _submitCode(),
                  decoration: InputDecoration(
                    labelText: 'Mã khôi phục',
                    errorText: _error,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                FilledButton(
                  onPressed: _submitCode,
                  child: const Text('Tiếp tục'),
                ),
                if (!widget.guard.hasRecoveryCode) ...[
                  const SizedBox(height: AppSpace.lg),
                  const StatusBanner(
                    type: StatusType.warning,
                    title: 'Máy này chưa có mã khôi phục',
                    message:
                        'Chỉ còn cách xóa dữ liệu app: Cài đặt của máy → Ứng '
                        'dụng → SafeFamily → Bộ nhớ → Xóa dữ liệu (mất danh '
                        'bạ, ảnh và cài đặt).',
                  ),
                ],
              ] else
                PinSetupView(onCompleted: _reset),
            ],
          ),
        ),
      ),
    );
  }
}
