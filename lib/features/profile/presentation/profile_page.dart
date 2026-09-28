import 'package:flutter/material.dart';

import '../../../core/constants/app_languages.dart';
import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/services/external_launcher.dart';
import '../../../core/settings/voice_language_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/confirm_delete_dialog.dart';
import '../../../core/widgets/initial_avatar.dart';
import '../data/family_contact.dart';
import '../data/local_profile_repository.dart';
import '../data/profile_repository.dart';
import '../../parental/presentation/security_settings_page.dart';
import '../../parental/presentation/unlock_log_page.dart';
import 'profile_controller.dart';
import 'settings_page.dart';
import 'widgets/contact_card.dart';
import 'widgets/contact_dialog.dart';
import 'widgets/parent_name_dialog.dart';

/// S02 — Cá nhân: hồ sơ phụ huynh, nút mở YouTube, danh bạ gia đình (mục 2).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.repository, this.launcher});

  /// Mặc định lưu trên máy ([LocalProfileRepository]).
  final ProfileRepository? repository;

  /// Mặc định mở app ngoài bằng url_launcher ([UrlExternalLauncher]).
  final ExternalLauncher? launcher;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileController _controller;
  late final ExternalLauncher _launcher;

  @override
  void initState() {
    super.initState();
    _launcher = widget.launcher ?? const UrlExternalLauncher();
    _controller = ProfileController(
      widget.repository ?? LocalProfileRepository(),
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String message) => showAppSnackBar(context, message);

  /// Chạy thao tác ghi dữ liệu; lỗi lưu trữ thì báo SnackBar thay vì crash.
  Future<void> _save(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) _snack(done);
    } catch (_) {
      if (mounted) _snack('Không lưu được, hãy thử lại.');
    }
  }

  Future<void> _editParentName() async {
    if (!await ParentGate.childAction(context, 'Sửa tên phụ huynh')) return;
    if (!mounted) return;
    final name = await ParentNameDialog.show(
      context,
      _controller.hasParentName ? _controller.parentName : '',
    );
    if (name == null) return;
    await _save(() => _controller.renameParent(name), 'Đã lưu tên.');
  }

  Future<void> _openYouTube() async {
    final ok = await _launcher.openYouTube();
    if (!ok && mounted) _snack('Không mở được YouTube.');
  }

  Future<void> _onContactTap(FamilyContact contact) async {
    if (!contact.hasPhone) return _editContact(contact, focusPhone: true);
    // Bấm gọi người nhà KHÔNG bao giờ bị khóa.
    final ok = await _launcher.openDialer(contact.phone);
    if (!ok && mounted) _snack('Không mở được app Điện thoại.');
  }

  Future<void> _addContact() async {
    if (!await ParentGate.childAction(context, 'Thêm liên hệ')) return;
    if (!mounted) return;
    final draft = await ContactDialog.show(context);
    if (draft == null) return;
    await _save(
      () => _controller.addContact(label: draft.label, phone: draft.phone),
      'Đã thêm ${draft.label}.',
    );
  }

  Future<void> _editContact(
    FamilyContact contact, {
    bool focusPhone = false,
  }) async {
    if (!await ParentGate.childAction(
      context,
      'Sửa liên hệ ${contact.label}',
    )) {
      return;
    }
    if (!mounted) return;
    final draft = await ContactDialog.show(
      context,
      initial: contact,
      focusPhone: focusPhone,
    );
    if (draft == null) return;
    await _save(
      () => _controller.updateContact(
        contact.copyWith(label: draft.label, phone: draft.phone),
      ),
      'Đã lưu ${draft.label}.',
    );
  }

  Future<void> _deleteContact(FamilyContact contact) async {
    if (!await ParentGate.childAction(
      context,
      'Xóa liên hệ ${contact.label}',
    )) {
      return;
    }
    if (!mounted) return;
    final confirmed = await confirmDelete(
      context,
      title: 'Xóa liên hệ ${contact.label}?',
      message: 'Liên hệ sẽ bị xóa khỏi danh bạ gia đình.',
    );
    if (!confirmed) return;
    await _save(
      () => _controller.deleteContact(contact.id),
      'Đã xóa ${contact.label}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_controller.loadError != null) {
            return _LoadError(onRetry: _controller.load);
          }
          return _buildContent(context);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final contacts = _controller.contacts;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        _ParentHeader(
          name: _controller.parentName,
          hasName: _controller.hasParentName,
          onEdit: _editParentName,
        ),
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _openYouTube,
            icon: const Icon(Icons.smart_display_rounded, size: AppSize.iconLg),
            label: const Text('Mở YouTube'),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        Row(
          children: [
            Expanded(
              child: Text(
                'Danh bạ gia đình',
                style: theme.textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              onPressed: _addContact,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Thêm'),
            ),
          ],
        ),
        Text(
          'Chạm vào thẻ để gọi.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (contacts.isEmpty)
          _EmptyContacts(onAdd: _addContact)
        else
          for (final contact in contacts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: ContactCard(
                key: ValueKey(contact.id),
                contact: contact,
                onTap: () => _onContactTap(contact),
                onEdit: () => _editContact(contact),
                onDelete: () => _deleteContact(contact),
              ),
            ),
        const SizedBox(height: AppSpace.md),
        if (ParentGuardScope.maybeOf(context) case final guard?) ...[
          _ParentalControlsCard(guard: guard, onOpen: _openParentArea),
          const SizedBox(height: AppSpace.md),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Cài đặt'),
            subtitle: Text(
              'Ngôn ngữ giọng nói: '
              '${(VoiceLanguageScope.maybeOf(context)?.language ?? AppLanguage.defaultVoice).nativeName}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openParentArea('Mở Cài đặt', const SettingsPage()),
          ),
        ),
      ],
    );
  }

  /// Vào khu vực phụ huynh: xác thực (nếu cần) rồi mở [page].
  Future<void> _openParentArea(String action, Widget page) async {
    final navigator = Navigator.of(context);
    if (!await ParentGate.parentArea(context, action)) return;
    await navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

/// Khóa phụ huynh: chế độ trẻ em, bảo mật, nhật ký mở khóa.
class _ParentalControlsCard extends StatelessWidget {
  const _ParentalControlsCard({required this.guard, required this.onOpen});

  final ParentGuard guard;
  final Future<void> Function(String action, Widget page) onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.child_care_rounded),
            title: const Text('Chế độ trẻ em'),
            subtitle: Text(
              guard.childMode
                  ? 'Đang bật — thoát cần xác thực phụ huynh.'
                  : 'Bật khi đưa máy cho con. Thoát cần vân tay/PIN.',
            ),
            value: guard.childMode,
            onChanged: (on) => guard.setChildMode(
              on,
              promptPin: ParentGate.promptFor(context),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Bảo mật & khóa phụ huynh'),
            subtitle: const Text('Mã PIN, vân tay/khuôn mặt, thời gian chờ'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () =>
                onOpen('Mở cài đặt bảo mật', const SecuritySettingsPage()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('Nhật ký mở khóa'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onOpen('Xem nhật ký mở khóa', const UnlockLogPage()),
          ),
        ],
      ),
    );
  }
}

class _ParentHeader extends StatelessWidget {
  const _ParentHeader({
    required this.name,
    required this.hasName,
    required this.onEdit,
  });

  final String name;
  final bool hasName;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.xs,
            AppSpace.lg,
          ),
          child: Row(
            children: [
              // Chưa đặt tên: hiện icon người thay vì chữ "H" của "Phụ huynh".
              InitialAvatar(hasName ? name : null),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    Text(
                      hasName ? 'Phụ huynh' : 'Chạm để đặt tên của bạn',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sửa tên',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
      child: Column(
        children: [
          Icon(
            Icons.contacts_outlined,
            size: AppSize.avatarMd,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: AppSpace.sm),
          Text('Chưa có liên hệ nào', style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppSpace.md),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Thêm liên hệ'),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Không đọc được dữ liệu đã lưu.'),
            const SizedBox(height: AppSpace.md),
            FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
