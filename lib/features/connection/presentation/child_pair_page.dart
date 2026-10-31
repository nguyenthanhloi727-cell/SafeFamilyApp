import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/connection_session.dart';
import '../../../core/theme/app_tokens.dart';
import 'server_address_field.dart';

/// Máy con: nhập mã 6 số do mẹ tạo. Đúng thì nhận token thiết bị và thành máy con.
class ChildPairPage extends StatefulWidget {
  const ChildPairPage({super.key});

  @override
  State<ChildPairPage> createState() => _ChildPairPageState();
}

class _ChildPairPageState extends State<ChildPairPage> {
  final _code = TextEditingController();
  ServerAddressController? _address;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _address ??= ServerAddressController(ConnectionScope.of(context));
  }

  @override
  void dispose() {
    _code.dispose();
    _address?.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'Mã gồm đúng 6 số.');
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
      await api.claimPairingCode(_code.text);
      await session.setMode(ConnectionMode.child);
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
      appBar: AppBar(title: const Text('Kết nối với máy mẹ')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          const Text(
            'Nhờ mẹ mở SafeFamily → Kết nối gia đình → Tạo mã, rồi nhập mã đó vào đây.',
          ),
          const SizedBox(height: AppSpace.lg),
          if (_address != null) ServerAddressField(controller: _address!),
          const SizedBox(height: AppSpace.md),
          TextField(
            key: const Key('pair-code'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'Mã 6 số'),
          ),
          if (_error != null)
            Text(
              _error!,
              key: const Key('pair-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            key: const Key('pair-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kết nối'),
          ),
        ],
      ),
    );
  }
}
