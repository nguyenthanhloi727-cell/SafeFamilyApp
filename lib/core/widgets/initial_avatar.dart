import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Chữ cái đầu của từ cuối (tên riêng tiếng Việt): "Nguyễn Thành Lợi" → "L".
String initialOf(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  final last = words.isEmpty ? '' : words.last;
  return last.isEmpty ? '?' : last.characters.first.toUpperCase();
}

/// Ảnh đại diện dạng chữ cái đầu; [name] `null` thì hiện icon người.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.name, {super.key, this.size = AppSize.avatarMd});

  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = this.name;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: name == null
          ? Icon(Icons.person_rounded, size: size / 2)
          : Text(
              initialOf(name),
              style:
                  (size >= AppSize.avatarLg
                          ? theme.textTheme.displaySmall
                          : size >= AppSize.avatarMd
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.titleMedium)
                      ?.copyWith(color: scheme.onPrimaryContainer),
            ),
    );
  }
}
