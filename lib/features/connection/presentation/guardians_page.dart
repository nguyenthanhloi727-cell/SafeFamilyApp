import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/confirm_delete_dialog.dart';

/// Người giám hộ thứ 2 (API-02): chủ gia đình mời bố/mẹ còn lại bằng mã 8 số,
/// xóa người đó; người được mời có thể tự rời gia đình.
class GuardiansPage extends StatefulWidget {
  const GuardiansPage({super.key});

  @override
  State<GuardiansPage> createState() => _GuardiansPageState();
}

class _GuardiansPageState extends State<GuardiansPage> {
  FamilyInfo? _family;
  PairingCode? _code;
  String? _error;
  bool _busy = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _reload();
    }
  }

  Future<void> _reload() async {
    final api = ApiScope.of(context);
    try {
      final family = await api.family();
      if (mounted) setState(() => _family = family);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _invite() async {
    final api = ApiScope.of(context);
    if (!await ParentGate.always(context, 'Mời người giám hộ')) return;
    setState(() => _busy = true);
    try {
      final code = await api.inviteGuardian();
      if (mounted) setState(() => _code = code);
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(FamilyMember member) async {
    final api = ApiScope.of(context);
    if (!await ParentGate.always(context, 'Xóa người giám hộ')) return;
    if (!mounted) return;
    final confirmed = await confirmDelete(
      context,
      title: 'Xóa ${member.email}?',
      message: 'Người này sẽ không còn quản lý máy của con được nữa.',
    );
    if (!confirmed) return;
    try {
      await api.removeGuardian(member.id);
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<void> _leave() async {
    final api = ApiScope.of(context);
    final navigator = Navigator.of(context);
    if (!await ParentGate.always(context, 'Rời gia đình')) return;
    if (!mounted) return;
    final confirmed = await confirmDelete(
      context,
      title: 'Rời gia đình?',
      message: 'Máy này sẽ không còn quản lý máy của con nữa.',
    );
    if (!confirmed) return;
    try {
      await api.leaveFamily();
      if (navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = _family;
    return Scaffold(
      appBar: AppBar(title: const Text('Người giám hộ')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          if (_error != null) Text(_error!),
          if (family == null && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (family != null) ...[
            Text(family.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpace.sm),
            for (final m in family.members)
              ListTile(
                key: Key('guardian-${m.id}'),
                leading: Icon(
                  m.isOwner ? Icons.star_rounded : Icons.person_outline,
                ),
                title: Text(m.isMe ? '${m.email} (bạn)' : m.email),
                subtitle: Text(m.isOwner ? 'Chủ gia đình' : 'Người giám hộ'),
                trailing: family.isOwner && !m.isMe
                    ? IconButton(
                        tooltip: 'Xóa',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => _remove(m),
                      )
                    : null,
              ),
            const SizedBox(height: AppSpace.lg),
            if (family.isOwner && family.members.length < 2) ...[
              FilledButton.icon(
                key: const Key('invite-guardian'),
                onPressed: _busy ? null : _invite,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Mời người giám hộ thứ 2'),
              ),
              if (_code != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                  child: Column(
                    children: [
                      SelectableText(
                        _code!.code,
                        key: const Key('guardian-code-value'),
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const Text(
                        'Nhập mã này khi đăng ký trên máy kia trong 30 phút (dùng một lần).',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
            if (!family.isOwner)
              OutlinedButton(
                key: const Key('leave-family'),
                onPressed: _leave,
                child: const Text('Rời gia đình'),
              ),
          ],
        ],
      ),
    );
  }
}
