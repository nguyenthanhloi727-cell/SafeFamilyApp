import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../data/family_contact.dart';
import '../../data/phone_number.dart';

/// Tên gọi chọn nhanh bằng chip.
const familyLabelPresets = ['Mẹ', 'Bố', 'Ông', 'Bà', 'Anh', 'Chị', 'Em', 'Con'];
const _otherLabel = 'Khác';

/// Kết quả hộp thoại: tên gọi + số đã chuẩn hoá (rỗng = chưa có số).
typedef ContactDraft = ({String label, String phone});

/// S03a — Hộp thoại thêm/sửa liên hệ.
class ContactDialog extends StatefulWidget {
  const ContactDialog({super.key, this.initial, this.focusPhone = false});

  /// `null` = thêm mới.
  final FamilyContact? initial;

  /// Mở để nhập số cho liên hệ chưa có số.
  final bool focusPhone;

  static Future<ContactDraft?> show(
    BuildContext context, {
    FamilyContact? initial,
    bool focusPhone = false,
  }) {
    return showDialog<ContactDraft>(
      context: context,
      builder: (_) => ContactDialog(initial: initial, focusPhone: focusPhone),
    );
  }

  @override
  State<ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<ContactDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customLabel = TextEditingController();
  final _phone = TextEditingController();

  /// Chip đang chọn: một trong [familyLabelPresets] hoặc [_otherLabel].
  String? _selected;
  bool _showLabelError = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      if (familyLabelPresets.contains(initial.label)) {
        _selected = initial.label;
      } else {
        _selected = _otherLabel;
        _customLabel.text = initial.label;
      }
      _phone.text = initial.phone;
    }
  }

  @override
  void dispose() {
    _customLabel.dispose();
    _phone.dispose();
    super.dispose();
  }

  String get _title {
    final initial = widget.initial;
    if (initial == null) return 'Thêm liên hệ';
    return widget.focusPhone ? 'Nhập số cho ${initial.label}' : 'Sửa liên hệ';
  }

  void _save() {
    final labelMissing = _selected == null;
    setState(() => _showLabelError = labelMissing);
    final formValid = _formKey.currentState!.validate();
    if (labelMissing || !formValid) return;

    final label = _selected == _otherLabel
        ? _customLabel.text.trim()
        : _selected!;
    Navigator.of(context)
        .pop((label: label, phone: normalizePhone(_phone.text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: Text(_title),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tên gọi', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                for (final label in [...familyLabelPresets, _otherLabel])
                  ChoiceChip(
                    label: Text(label),
                    selected: _selected == label,
                    onSelected: (_) => setState(() {
                      _selected = label;
                      _showLabelError = false;
                    }),
                  ),
              ],
            ),
            if (_showLabelError)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  'Chọn tên gọi',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            if (_selected == _otherLabel) ...[
              const SizedBox(height: AppSpace.md),
              TextFormField(
                key: const Key('custom-label-field'),
                controller: _customLabel,
                autofocus: widget.initial == null,
                maxLength: 30,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tên gọi khác',
                  hintText: 'Ví dụ: Cô Lan',
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Nhập tên gọi' : null,
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            TextFormField(
              key: const Key('phone-field'),
              controller: _phone,
              autofocus: widget.focusPhone,
              keyboardType: TextInputType.phone,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: 'Số điện thoại',
                hintText: '0901 234 567',
                helperText: widget.focusPhone ? null : 'Có thể để trống',
              ),
              validator: (value) {
                final text = value ?? '';
                if (text.trim().isEmpty) {
                  return widget.focusPhone ? 'Nhập số điện thoại' : null;
                }
                return validatePhone(text);
              },
              onFieldSubmitted: (_) => _save(),
            ),
          ],
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
