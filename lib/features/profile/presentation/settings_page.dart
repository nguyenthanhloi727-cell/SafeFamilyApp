import 'package:flutter/material.dart';

import '../../../core/constants/app_info.dart';
import '../../../core/settings/voice_language_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/language_picker.dart';

/// S04 — Cài đặt: ngôn ngữ giọng nói mặc định, âm báo, giới thiệu.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = VoiceLanguageScope.of(context);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        children: [
          section('Báo thức bằng giọng nói'),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Ngôn ngữ giọng nói'),
            subtitle: Text(settings.language.nativeName),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final picked = await showLanguagePicker(
                context,
                selected: settings.language,
              );
              if (picked != null) await settings.setLanguage(picked);
            },
          ),
          const ListTile(
            leading: Icon(Icons.music_note_outlined),
            title: Text('Âm báo'),
            subtitle: Text(
              'Báo thức được đặt vào app Đồng hồ của máy — '
              'âm báo chọn trong app Đồng hồ.',
            ),
          ),
          section('Giới thiệu'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text(AppInfo.displayName),
            subtitle: const Text('Đồ án nhóm môn Flutter'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppInfo.displayName,
            ),
          ),
        ],
      ),
    );
  }
}
