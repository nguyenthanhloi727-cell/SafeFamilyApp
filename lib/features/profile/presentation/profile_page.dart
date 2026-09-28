import 'package:flutter/material.dart';

import '../../../core/constants/app_languages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/step_notice.dart';

/// S02 — Cá nhân: hồ sơ phụ huynh, danh bạ gia đình, YouTube, cài đặt (giữ chỗ).
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void notYet() => showNotYetSnackBar(context, 'Sẽ làm ở bước 3.');

    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          const StepNotice(
            'Hồ sơ, danh bạ gia đình và nút YouTube: sẽ làm ở bước 3.',
          ),
          const SizedBox(height: AppSpace.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: AppSize.avatarMd / 2,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: const Icon(
                      Icons.person_rounded,
                      size: AppSize.iconLg,
                    ),
                  ),
                  const SizedBox(width: AppSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phụ huynh', style: theme.textTheme.titleMedium),
                        Text(
                          'Chưa có thông tin hồ sơ',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.contacts_outlined),
                  title: const Text('Danh bạ gia đình'),
                  subtitle: const Text('Mẹ, Bố, Con…'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: notYet,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.smart_display_outlined),
                  title: const Text('Mở YouTube'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: notYet,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Cài đặt'),
                  subtitle: Text(
                    'Ngôn ngữ giọng nói: ${AppLanguage.defaultVoice.nativeName}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: notYet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
