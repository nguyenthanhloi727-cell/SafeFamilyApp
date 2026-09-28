import 'package:flutter/material.dart';

import '../constants/app_languages.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// C8 — Chọn 1 trong 5 ngôn ngữ (bottom sheet). Trả về `null` nếu đóng.
///
/// [unavailable]: ngôn ngữ máy chưa có gói nhận giọng nói (vẫn chọn được).
Future<AppLanguage?> showLanguagePicker(
  BuildContext context, {
  required AppLanguage selected,
  String title = 'Ngôn ngữ giọng nói',
  Set<AppLanguage> unavailable = const {},
}) {
  return showModalBottomSheet<AppLanguage>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final warning = theme.extension<AppColors>()!.warning;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                0,
                AppSpace.xl,
                AppSpace.sm,
              ),
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            for (final language in AppLanguage.values)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.xl,
                ),
                leading: Icon(
                  language == selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: language == selected
                      ? theme.colorScheme.primary
                      : null,
                ),
                title: Text(language.nativeName),
                subtitle: Text(
                  unavailable.contains(language)
                      ? 'Máy chưa có gói nhận giọng nói'
                      : _capitalize(language.vietnameseName),
                  style: unavailable.contains(language)
                      ? TextStyle(color: warning)
                      : null,
                ),
                selected: language == selected,
                onTap: () => Navigator.of(context).pop(language),
              ),
          ],
        ),
      );
    },
  );
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
