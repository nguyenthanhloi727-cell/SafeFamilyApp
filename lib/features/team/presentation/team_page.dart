import 'package:flutter/material.dart';

import '../../../core/constants/feature_flags.dart';
import '../../../core/services/external_launcher.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/confirm_delete_dialog.dart';
import '../data/member_photo.dart';
import '../data/member_photo_store.dart';
import '../data/photo_picker.dart';
import '../data/team_member.dart';
import '../data/team_repository.dart';
import 'team_controller.dart';
import 'widgets/member_card.dart';

/// S11 — Nhóm: thẻ thành viên lướt ngang (mục 6).
class TeamPage extends StatefulWidget {
  const TeamPage({
    super.key,
    this.repository,
    this.photoStore,
    this.photoPicker,
    this.launcher,
    this.photoUploadEnabled = kTeamPhotoUploadEnabled,
  });

  final TeamRepository? repository;
  final MemberPhotoStore? photoStore;
  final PhotoPicker? photoPicker;
  final ExternalLauncher? launcher;

  /// MỞ / KHÓA tải ảnh — mặc định theo [kTeamPhotoUploadEnabled].
  final bool photoUploadEnabled;

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  // < 1 để thẻ kế bên ló ra ở mép, người dùng biết lướt được.
  final _pageController = PageController(viewportFraction: 0.86);
  late final TeamController _controller;
  late final PhotoPicker _picker;
  late final ExternalLauncher _launcher;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _picker = widget.photoPicker ?? ImagePickerPhotoPicker();
    _launcher = widget.launcher ?? const UrlExternalLauncher();
    _controller = TeamController(
      widget.repository ?? AssetTeamRepository(),
      widget.photoStore ?? LocalMemberPhotoStore(),
    )..load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _snack(String message) => showAppSnackBar(context, message);

  Future<void> _uploadPhoto(TeamMember member) async {
    try {
      final path = await _picker.pickFromGallery();
      if (path == null) return; // bấm hủy
      await _controller.setUploadedPhoto(member, path);
      if (mounted) _snack('Đã lưu ảnh của ${member.fullName}.');
    } catch (_) {
      if (mounted) _snack('Không lấy được ảnh, hãy thử lại.');
    }
  }

  Future<void> _deletePhoto(TeamMember member) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Xóa ảnh?',
      message: 'Xóa ảnh đã tải lên của ${member.fullName}.',
    );
    if (!confirmed) return;
    try {
      await _controller.removeUploadedPhoto(member);
    } catch (_) {
      if (mounted) _snack('Không xóa được ảnh, hãy thử lại.');
    }
  }

  Future<void> _openEmail(String email) async {
    final ok = await _launcher.openEmail(email);
    if (!ok && mounted) _snack('Không mở được app mail.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nhóm')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_controller.loadError != null || _controller.members.isEmpty) {
            return _LoadError(onRetry: _controller.load);
          }
          return _buildPages(context);
        },
      ),
    );
  }

  Widget _buildPages(BuildContext context) {
    final members = _controller.members;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: members.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final member = members[index];
              final photo = _controller.photoOf(member);
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xs,
                  AppSpace.lg,
                  AppSpace.xs,
                  AppSpace.sm,
                ),
                child: MemberCard(
                  key: ValueKey(member.id),
                  member: member,
                  photo: photo,
                  // Đã có ảnh cố định thì ảnh tải lên không bao giờ hiện → ẩn nút.
                  showPhotoControls:
                      widget.photoUploadEnabled && photo is! AssetMemberPhoto,
                  onUpload: () => _uploadPhoto(member),
                  onDeletePhoto: () => _deletePhoto(member),
                  onEmailTap: _openEmail,
                ),
              );
            },
          ),
        ),
        _PageIndicator(count: members.length, current: _page),
        const SizedBox(height: AppSpace.lg),
      ],
    );
  }
}

/// Chấm chỉ trang + chữ "1/4".
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            width: i == current ? AppSpace.xl : AppSpace.sm,
            height: AppSpace.sm,
            decoration: BoxDecoration(
              color: i == current ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        const SizedBox(width: AppSpace.md),
        Text(
          '${current + 1}/$count',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
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
            const Text(
              'Không đọc được thông tin nhóm (assets/team/members.json).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.md),
            FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
