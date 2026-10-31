import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';

/// Khớp `[MinLength(8), MaxLength(128)]` ở server (API-03); server vẫn là nơi quyết định.
const _minPassword = 8;

/// Mẹ đổi mật khẩu (API-03). Phiên này được giữ, các phiên khác (máy khác) bị đăng xuất.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String? invalid;
    if (_current.text.isEmpty) {
      invalid = 'Nhập mật khẩu hiện tại.';
    } else if (_next.text.length < _minPassword) {
      invalid = 'Mật khẩu mới phải từ $_minPassword ký tự.';
    } else if (_next.text.length > 128) {
      invalid = 'Mật khẩu mới tối đa 128 ký tự.';
    } else if (_next.text == _current.text) {
      invalid = 'Mật khẩu mới phải khác mật khẩu hiện tại.';
    } else if (_next.text != _again.text) {
      invalid = 'Hai lần nhập mật khẩu mới chưa giống nhau.';
    } else {
      invalid = null;
    }
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final api = ApiScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await ParentGate.always(context, 'Đổi mật khẩu')) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.changePassword(_current.text, _next.text);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Đã đổi mật khẩu. Các máy khác cần đăng nhập lại.'),
        ),
      );
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đổi mật khẩu')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          _PasswordField(
            fieldKey: const Key('current-password'),
            controller: _current,
            label: 'Mật khẩu hiện tại',
          ),
          const SizedBox(height: AppSpace.md),
          _PasswordField(
            fieldKey: const Key('new-password'),
            controller: _next,
            label: 'Mật khẩu mới (từ $_minPassword ký tự)',
          ),
          const SizedBox(height: AppSpace.md),
          _PasswordField(
            fieldKey: const Key('new-password-again'),
            controller: _again,
            label: 'Nhập lại mật khẩu mới',
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              _error!,
              key: const Key('account-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            key: const Key('change-password-submit'),
            onPressed: _busy ? null : _submit,
            child: const Text('Đổi mật khẩu'),
          ),
        ],
      ),
    );
  }
}

/// Quên mật khẩu (API-03): nhập email → nhận mã 6 số qua thư → nhập mã + mật khẩu mới.
/// Mã hết hạn sau 30 phút (xem server `PasswordResetRules`); server luôn báo thành công ở bước 1 để không lộ email nào có tài khoản.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _next = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Nhập email đã đăng ký.');
      return;
    }
    final api = ApiScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.forgotPassword(email);
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'Mã gồm đúng 6 chữ số.');
      return;
    }
    if (_next.text.length < _minPassword || _next.text.length > 128) {
      setState(() => _error = 'Mật khẩu mới từ $_minPassword đến 128 ký tự.');
      return;
    }
    final api = ApiScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.resetPassword(_email.text.trim(), _code.text.trim(), _next.text);
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã đặt mật khẩu mới. Hãy đăng nhập.')),
      );
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quên mật khẩu')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          TextField(
            key: const Key('forgot-email'),
            controller: _email,
            enabled: !_sent,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email đã đăng ký',
              prefixIcon: Icon(Icons.email_rounded),
            ),
          ),
          if (!_sent) ...[
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              key: const Key('forgot-send'),
              onPressed: _busy ? null : _send,
              child: const Text('Gửi mã qua email'),
            ),
          ] else ...[
            const SizedBox(height: AppSpace.md),
            const Text(
              'Nếu email này có tài khoản, một mã 6 số đã được gửi tới. '
              'Mã dùng được trong 30 phút, nhập sai 5 lần thì phải xin mã mới.',
              key: Key('forgot-sent-note'),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              key: const Key('forgot-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Mã 6 số',
                prefixIcon: Icon(Icons.pin_rounded),
              ),
            ),
            _PasswordField(
              fieldKey: const Key('forgot-new-password'),
              controller: _next,
              label: 'Mật khẩu mới (từ $_minPassword ký tự)',
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              key: const Key('forgot-reset'),
              onPressed: _busy ? null : _reset,
              child: const Text('Đặt mật khẩu mới'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _sent = false;
                      _error = null;
                    }),
              child: const Text('Gửi lại mã'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              _error!,
              key: const Key('account-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hộp xác nhận xóa tài khoản: nhập lại mật khẩu rồi xóa vĩnh viễn. Trả `true` khi đã xóa.
/// Gọi sau `ParentGate.always`.
Future<bool> showDeleteAccountDialog(BuildContext context) async {
  final api = ApiScope.of(context);
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteAccountDialog(api: api),
  );
  return done ?? false;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.api});

  final ApiClient api;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.deleteAccount(_password.text);
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Xóa tài khoản?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Toàn bộ dữ liệu gia đình trên máy chủ sẽ bị xóa vĩnh viễn: máy con '
            'đã ghép, luật, lịch sử vị trí, báo cáo và cảnh báo. Máy con sẽ mất '
            'kết nối. Không hoàn tác được.',
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const Key('delete-password'),
            controller: _password,
            obscureText: true,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                _error!,
                key: const Key('account-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _busy || _password.text.isEmpty ? null : _delete,
          child: const Text('Xóa vĩnh viễn'),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.fieldKey,
    required this.controller,
    required this.label,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      obscureText: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_rounded),
      ),
    );
  }
}
