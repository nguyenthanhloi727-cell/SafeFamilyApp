import 'package:flutter/material.dart';

import '../../../core/network/api_scope.dart';
import '../../../core/network/connection_session.dart';
import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/initial_avatar.dart';
import '../data/local_profile_repository.dart';
import '../data/profile_repository.dart';
import '../../connection/presentation/account_pages.dart';
import '../../connection/presentation/child_contacts_page.dart';
import '../../connection/presentation/guardians_page.dart';
import '../../parental/presentation/device_protection_page.dart';
import '../../parental/presentation/security_settings_page.dart';
import '../../parental/presentation/unlock_log_page.dart';
import 'profile_controller.dart';
import 'settings_page.dart';
import 'widgets/parent_name_dialog.dart';

/// S02 — Cá nhân: hồ sơ phụ huynh.
///
/// Trên máy mẹ đã đăng nhập đây là tab **Tài khoản**: thêm email đăng nhập,
/// người giám hộ thứ 2, đổi mật khẩu, danh bạ của con, đăng xuất, xóa tài khoản.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.repository});

  /// Mặc định lưu trên máy ([LocalProfileRepository]).
  final ProfileRepository? repository;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileController _controller;

  @override
  void initState() {
    super.initState();
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
    if (!await ParentGate.parentArea(context, 'Sửa tên phụ huynh')) return;
    if (!mounted) return;
    final name = await ParentNameDialog.show(
      context,
      _controller.hasParentName ? _controller.parentName : '',
    );
    if (name == null) return;
    await _save(() => _controller.renameParent(name), 'Đã lưu tên.');
  }

  bool get _isParentAccount {
    final connection = ConnectionScope.maybeOf(context);
    return connection != null &&
        connection.mode == ConnectionMode.parent &&
        connection.isParentLoggedIn;
  }

  /// API-03: thu hồi phiên trên server rồi xóa phiên cục bộ; app tự về màn đăng nhập.
  Future<void> _logout() async {
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await ParentGate.always(context, 'Đăng xuất máy mẹ')) return;
    final revoked = await api.logout();
    if (!revoked) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Đã đăng xuất trên máy này, nhưng chưa báo được cho máy chủ '
            '(không có mạng).',
          ),
        ),
      );
    }
  }

  /// API-03: xóa tài khoản + toàn bộ dữ liệu gia đình (khóa phụ huynh, rồi nhập lại mật khẩu).
  Future<void> _deleteAccount() async {
    if (!await ParentGate.always(context, 'Xóa tài khoản')) return;
    if (!mounted) return;
    await showDeleteAccountDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isParentAccount ? 'Tài khoản' : 'Cá nhân')),
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
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        if (_isParentAccount) ...[
          _AccountCard(
            email: ConnectionScope.of(context).email ?? 'Máy mẹ',
            onGuardians: () =>
                _openParentArea('Người giám hộ', const GuardiansPage()),
            onChangePassword: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ChangePasswordPage(),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        _ParentHeader(
          name: _controller.parentName,
          hasName: _controller.hasParentName,
          onEdit: _editParentName,
        ),
        const SizedBox(height: AppSpace.lg),
        if (_isParentAccount) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const Key('account-child-contacts'),
              leading: const Icon(Icons.contacts_outlined),
              title: const Text('Danh bạ của con'),
              subtitle: const Text('Người nhà con gọi được, số SOS'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openParentArea(
                'Mở danh bạ của con',
                const ChildContactsPage(),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        if (ParentGuardScope.maybeOf(context) case final guard?) ...[
          _ParentalControlsCard(guard: guard, onOpen: _openParentArea),
          const SizedBox(height: AppSpace.md),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Cài đặt'),
            subtitle: const Text('Giao diện, giới thiệu'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openParentArea('Mở Cài đặt', const SettingsPage()),
          ),
        ),
        if (_isParentAccount) ...[
          const SizedBox(height: AppSpace.md),
          OutlinedButton(
            key: const Key('account-logout'),
            onPressed: _logout,
            child: const Text('Đăng xuất máy mẹ'),
          ),
          ListTile(
            key: const Key('account-delete'),
            leading: Icon(
              Icons.delete_forever_rounded,
              color: theme.colorScheme.error,
            ),
            title: const Text('Xóa tài khoản'),
            subtitle: const Text(
              'Xóa vĩnh viễn mọi dữ liệu gia đình trên máy chủ.',
            ),
            onTap: _deleteAccount,
          ),
        ],
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

/// Tài khoản máy mẹ: email đăng nhập, người giám hộ, đổi mật khẩu.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.email,
    required this.onGuardians,
    required this.onChangePassword,
  });

  final String email;
  final VoidCallback onGuardians;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            key: const Key('account-email'),
            leading: const Icon(Icons.account_circle_rounded),
            title: Text(email),
            subtitle: const Text('Email đăng nhập · Máy mẹ'),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('account-guardians'),
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('Người giám hộ thứ 2'),
            subtitle: const Text('Mời bố/mẹ còn lại cùng quản lý'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onGuardians,
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('account-change-password'),
            leading: const Icon(Icons.password_rounded),
            title: const Text('Đổi mật khẩu'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onChangePassword,
          ),
        ],
      ),
    );
  }
}

/// Khóa phụ huynh: bảo vệ máy, bảo mật, nhật ký mở khóa.
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
          ListTile(
            leading: const Icon(Icons.security_rounded),
            title: const Text('Bảo vệ máy'),
            subtitle: const Text('Chống tắt Trợ năng, chống gỡ SafeFamily'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () =>
                onOpen('Mở Bảo vệ máy', DeviceProtectionPage(guard: guard)),
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
