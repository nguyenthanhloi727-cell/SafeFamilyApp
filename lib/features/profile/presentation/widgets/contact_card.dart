import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/initial_avatar.dart';
import '../../data/family_contact.dart';

enum _ContactAction { edit, delete }

/// Thẻ liên hệ: chạm để gọi (hoặc nhập số nếu chưa có), menu Sửa / Xóa.
class ContactCard extends StatelessWidget {
  const ContactCard({
    super.key,
    required this.contact,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final FamilyContact contact;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appColors = theme.extension<AppColors>()!;
    final hasPhone = contact.hasPhone;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: hasPhone
              ? 'Gọi ${contact.label}'
              : 'Nhập số cho ${contact.label}',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.xs,
              AppSpace.md,
            ),
            child: Row(
              children: [
                InitialAvatar(contact.label),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contact.label, style: theme.textTheme.titleMedium),
                      Text(
                        hasPhone ? contact.phone : 'Chạm để thêm số',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: hasPhone
                              ? scheme.onSurfaceVariant
                              : appColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  hasPhone ? Icons.call_rounded : Icons.add_ic_call_outlined,
                  color: hasPhone ? scheme.primary : scheme.onSurfaceVariant,
                ),
                PopupMenuButton<_ContactAction>(
                  tooltip: 'Tùy chọn ${contact.label}',
                  onSelected: (action) => switch (action) {
                    _ContactAction.edit => onEdit(),
                    _ContactAction.delete => onDelete(),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ContactAction.edit,
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Sửa'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ContactAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Xóa'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
