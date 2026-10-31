import 'package:flutter/material.dart';

import '../../../core/network/connection_session.dart';

/// Ô nhập địa chỉ máy chủ API, dùng chung cho màn đăng nhập mẹ và ghép đôi con.
/// Gọi [commit] trước khi gọi API để lưu địa chỉ vào phiên.
class ServerAddressController {
  ServerAddressController(ConnectionSession session)
    : text = TextEditingController(text: session.baseUrl),
      _session = session;

  final TextEditingController text;
  final ConnectionSession _session;

  Future<void> commit() => _session.setBaseUrl(text.text);

  void dispose() => text.dispose();
}

class ServerAddressField extends StatelessWidget {
  const ServerAddressField({super.key, required this.controller});

  final ServerAddressController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('server-address'),
      controller: controller.text,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'Địa chỉ máy chủ',
        helperText: 'Ví dụ: https://safefamily.example.com',
        prefixIcon: Icon(Icons.dns_rounded),
      ),
    );
  }
}
