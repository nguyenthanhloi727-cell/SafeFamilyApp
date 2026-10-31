import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/connection_session.dart';
import '../../../core/theme/app_tokens.dart';
import 'server_address_field.dart';

/// Máy mẹ: đăng nhập hoặc đăng ký (email + mật khẩu). Thành công thì máy này
/// thành máy mẹ và app vào màn chính.
class ParentLoginPage extends StatefulWidget {
  const ParentLoginPage({super.key});

  @override
  State<ParentLoginPage> createState() => _ParentLoginPageState();
}

class _ParentLoginPageState extends State<ParentLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  ServerAddressController? _address;
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _address ??= ServerAddressController(ConnectionScope.of(context));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _address?.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < (_register ? 8 : 1)) {
      setState(
        () => _error = _register
            ? 'Nhập email và mật khẩu từ 8 ký tự.'
            : 'Nhập email và mật khẩu.',
      );
      return;
    }
    final api = ApiScope.of(context);
    final session = ConnectionScope.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _address!.commit();
      if (_register) {
        await api.register(email, password);
      } else {
        await api.login(email, password);
      }
      await session.setMode(ConnectionMode.parent);
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
      appBar: AppBar(
        title: Text(_register ? 'Đăng ký máy mẹ' : 'Đăng nhập máy mẹ'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          if (_address != null) ServerAddressField(controller: _address!),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const Key('login-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_rounded),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const Key('login-password'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mật khẩu',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              _error!,
              key: const Key('login-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            key: const Key('login-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_register ? 'Đăng ký' : 'Đăng nhập'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _register = !_register),
            child: Text(
              _register
                  ? 'Đã có tài khoản? Đăng nhập'
                  : 'Chưa có tài khoản? Đăng ký',
            ),
          ),
        ],
      ),
    );
  }
}
