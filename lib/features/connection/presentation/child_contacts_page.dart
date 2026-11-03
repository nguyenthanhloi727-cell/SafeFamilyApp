import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/connection_session.dart';
import '../../../core/network/policy_schema.dart';
import '../../../core/network/policy_sync.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/confirm_delete_dialog.dart';
import '../../profile/data/family_contact.dart';
import '../../profile/presentation/widgets/contact_card.dart';
import '../../profile/presentation/widgets/contact_dialog.dart';

/// Máy mẹ sửa DANH BẠ CỦA CON (T11): thêm / sửa / xóa liên hệ, đánh dấu SOS.
/// Danh bạ nằm trong luật của máy con trên server (`policy.contacts`), mỗi thay đổi
/// ghi ngay qua [PolicySync]; máy con thấy sau lần đồng bộ kế tiếp.
class ChildContactsPage extends StatefulWidget {
  const ChildContactsPage({super.key});

  @override
  State<ChildContactsPage> createState() => _ChildContactsPageState();
}

class _ChildContactsPageState extends State<ChildContactsPage> {
  List<FamilyContact> _contacts = const [];
  bool _loading = true;
  String? _error;
  bool _started = false;

  PolicySync? get _sync => PolicySyncScope.maybeOf(context);
  int? get _childId => ConnectionScope.maybeOf(context)?.selectedChildId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final sync = _sync;
    final id = _childId;
    if (sync == null || id == null) {
      setState(() {
        _loading = false;
        _error = 'Chưa chọn máy con.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contacts = await sync.loadContacts(id);
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không đọc được danh bạ của con: ${e.message}';
      });
    }
  }

  /// Ghi [next] lên luật của máy con. Lỗi thì báo và giữ danh bạ cũ trên màn.
  Future<void> _apply(List<FamilyContact> next, String done) async {
    final sync = _sync;
    final id = _childId;
    if (sync == null || id == null) return;
    try {
      final saved = await sync.setContacts(id, next);
      if (!mounted) return;
      setState(() => _contacts = saved);
      showAppSnackBar(context, done);
    } on ApiException catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Chưa lưu được: ${e.message}');
        await _load();
      }
    }
  }

  Future<void> _add() async {
    if (_contacts.length >= PolicySchema.maxContacts) {
      showAppSnackBar(
        context,
        'Tối đa ${PolicySchema.maxContacts} liên hệ. Hãy xóa bớt một người trước.',
      );
      return;
    }
    if (!await ParentGate.parentArea(context, 'Thêm liên hệ cho con')) return;
    if (!mounted) return;
    final draft = await ContactDialog.show(context);
    if (draft == null || !mounted) return;
    if (draft.phone.isEmpty) {
      showAppSnackBar(context, 'Liên hệ của con cần có số điện thoại.');
      return;
    }
    await _apply([
      ..._contacts,
      FamilyContact(
        id: 'new',
        label: draft.label,
        phone: draft.phone,
        order: _contacts.length,
      ),
    ], 'Đã thêm ${draft.label}.');
  }

  Future<void> _edit(FamilyContact contact) async {
    if (!await ParentGate.parentArea(
      context,
      'Sửa liên hệ ${contact.label}',
    )) {
      return;
    }
    if (!mounted) return;
    final draft = await ContactDialog.show(context, initial: contact);
    if (draft == null || !mounted) return;
    if (draft.phone.isEmpty) {
      showAppSnackBar(context, 'Liên hệ của con cần có số điện thoại.');
      return;
    }
    await _apply([
      for (final c in _contacts)
        c.id == contact.id
            ? c.copyWith(label: draft.label, phone: draft.phone)
            : c,
    ], 'Đã lưu ${draft.label}.');
  }

  Future<void> _toggleSos(FamilyContact contact) async {
    final turnOn = !contact.emergency;
    if (turnOn && _contacts.where((c) => c.emergency).length >= PolicySchema.maxSos) {
      showAppSnackBar(
        context,
        'Tối đa ${PolicySchema.maxSos} số SOS. Hãy bỏ bớt một người trước.',
      );
      return;
    }
    if (!await ParentGate.parentArea(context, 'Đổi số SOS của con')) return;
    if (!mounted) return;
    await _apply([
      for (final c in _contacts)
        c.id == contact.id ? c.copyWith(emergency: turnOn) : c,
    ], turnOn ? '${contact.label} là số SOS của con.' : 'Đã bỏ SOS của ${contact.label}.');
  }

  Future<void> _delete(FamilyContact contact) async {
    if (!await ParentGate.parentArea(
      context,
      'Xóa liên hệ ${contact.label}',
    )) {
      return;
    }
    if (!mounted) return;
    final confirmed = await confirmDelete(
      context,
      title: 'Xóa liên hệ ${contact.label}?',
      message: 'Liên hệ sẽ biến mất khỏi danh bạ của con sau lần đồng bộ tới.',
    );
    if (!confirmed || !mounted) return;
    await _apply([
      for (final c in _contacts)
        if (c.id != contact.id) c,
    ], 'Đã xóa ${contact.label}.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh bạ của con'),
        actions: [
          IconButton(
            key: const Key('child-contacts-add'),
            tooltip: 'Thêm liên hệ',
            onPressed: _loading || _error != null ? null : _add,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: _body(theme),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.md),
              FilledButton(onPressed: _load, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Text(
          'Người nhà con có thể gọi ngay trên máy con (tối đa '
          '${PolicySchema.maxContacts} người, ${PolicySchema.maxSos} số SOS). '
          'Số SOS luôn nằm trên cùng và hiện cả trên màn chặn.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (_contacts.isEmpty)
          Padding(
            key: const Key('child-contacts-empty'),
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
            child: Column(
              children: [
                Icon(
                  Icons.contacts_outlined,
                  size: AppSize.avatarMd,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: AppSpace.sm),
                const Text('Con chưa có liên hệ nào'),
                const SizedBox(height: AppSpace.md),
                FilledButton.tonalIcon(
                  onPressed: _add,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Thêm liên hệ'),
                ),
              ],
            ),
          )
        else
          for (final contact in _contacts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: ContactCard(
                key: ValueKey('${contact.id}-${contact.phone}'),
                contact: contact,
                onTap: () => _edit(contact),
                onEdit: () => _edit(contact),
                onDelete: () => _delete(contact),
                onToggleEmergency: () => _toggleSos(contact),
              ),
            ),
      ],
    );
  }
}
