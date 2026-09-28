import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/initial_avatar.dart';
import '../../data/member_photo.dart';
import '../../data/team_member.dart';

/// C13 — Thẻ thành viên: ảnh lớn, họ tên, MSSV, email, vai trò, lớp.
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.member,
    required this.photo,
    required this.showPhotoControls,
    required this.onUpload,
    required this.onDeletePhoto,
    required this.onEmailTap,
  });

  final TeamMember member;
  final MemberPhoto photo;

  /// Hiện nút Tải ảnh lên / Đổi ảnh / Xóa ảnh (chế độ MỞ và chưa có ảnh cố định).
  final bool showPhotoControls;
  final VoidCallback onUpload;
  final VoidCallback onDeletePhoto;
  final ValueChanged<String> onEmailTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = member.email;
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          children: [
            _MemberPhotoView(photo: photo, name: member.fullName),
            if (showPhotoControls) ...[
              const SizedBox(height: AppSpace.sm),
              _PhotoControls(
                hasUploaded: photo is UploadedMemberPhoto,
                onUpload: onUpload,
                onDelete: onDeletePhoto,
              ),
            ],
            const SizedBox(height: AppSpace.md),
            Text(
              member.fullName,
              textAlign: TextAlign.center,
              softWrap: true,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpace.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpace.sm),
            _InfoRow(
              icon: Icons.badge_outlined,
              label: 'MSSV',
              value: member.studentId,
            ),
            _InfoRow(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              value: email,
              onTap: email == null ? null : () => onEmailTap(email),
            ),
            _InfoRow(
              icon: Icons.work_outline_rounded,
              label: 'Vai trò',
              value: member.role,
            ),
            _InfoRow(
              icon: Icons.school_outlined,
              label: 'Lớp',
              value: member.className,
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberPhotoView extends StatelessWidget {
  const _MemberPhotoView({required this.photo, required this.name});

  final MemberPhoto photo;
  final String name;

  @override
  Widget build(BuildContext context) {
    const size = AppSize.memberPhoto;
    final initials = InitialAvatar(name, size: size);
    Widget clip(Widget image) => ClipOval(
      child: SizedBox.square(dimension: size, child: image),
    );

    return Semantics(
      label: 'Ảnh của $name',
      image: true,
      child: switch (photo) {
        AssetMemberPhoto(:final assetPath) => clip(
          Image.asset(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => initials,
          ),
        ),
        UploadedMemberPhoto(:final filePath) => clip(
          Image.file(
            File(filePath),
            fit: BoxFit.cover,
            cacheWidth: 512,
            errorBuilder: (_, _, _) => initials,
          ),
        ),
        InitialsMemberPhoto() => initials,
      },
    );
  }
}

class _PhotoControls extends StatelessWidget {
  const _PhotoControls({
    required this.hasUploaded,
    required this.onUpload,
    required this.onDelete,
  });

  final bool hasUploaded;
  final VoidCallback onUpload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (!hasUploaded) {
      return OutlinedButton.icon(
        onPressed: onUpload,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Tải ảnh lên'),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpace.xs,
      children: [
        TextButton.icon(
          onPressed: onUpload,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Đổi ảnh'),
        ),
        TextButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Xóa ảnh'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = this.value;

    final valueText = value == null
        ? Text(
            'Chưa cập nhật',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.outline,
              fontStyle: FontStyle.italic,
            ),
          )
        : Text(
            value,
            softWrap: true,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: onTap == null ? null : scheme.primary,
              decoration: onTap == null ? null : TextDecoration.underline,
              decorationColor: scheme.primary,
            ),
          );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                valueText,
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: row,
    );
  }
}
