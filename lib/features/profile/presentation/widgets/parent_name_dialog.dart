import 'package:flutter/material.dart';

/// Hộp thoại sửa tên phụ huynh. Trả về tên mới, hoặc `null` nếu bấm Hủy.
class ParentNameDialog extends StatefulWidget {
  const ParentNameDialog({super.key, required this.initialName});

  final String initialName;

  static Future<String?> show(BuildContext context, String initialName) {
    return showDialog<String>(
      context: context,
      builder: (_) => ParentNameDialog(initialName: initialName),
    );
  }

  @override
  State<ParentNameDialog> createState() => _ParentNameDialogState();
}

class _ParentNameDialogState extends State<ParentNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tên phụ huynh'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Họ tên',
            hintText: 'Ví dụ: Nguyễn Văn A',
          ),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Nhập tên' : null,
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }
}
