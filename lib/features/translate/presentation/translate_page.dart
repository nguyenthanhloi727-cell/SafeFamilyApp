import 'package:flutter/material.dart';

import '../../../core/constants/app_languages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/step_notice.dart';

/// S06–S09 — Dịch: cặp ngôn ngữ nguồn ⇄ đích và 4 chế độ (giữ chỗ).
class TranslatePage extends StatefulWidget {
  const TranslatePage({super.key});

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  static const _modes = [
    (Icons.notes_rounded, 'Văn bản', 'Sẽ làm ở bước 6'),
    (Icons.mic_none_rounded, 'Giọng nói', 'Sẽ làm ở bước 6'),
    (Icons.image_outlined, 'Ảnh', 'Sẽ làm ở bước 6'),
    (Icons.videocam_outlined, 'Camera', 'Sẽ làm ở bước 7'),
  ];

  AppLanguage _source = AppLanguage.vietnamese;
  AppLanguage _target = AppLanguage.english;

  void _swap() => setState(() {
    final old = _source;
    _source = _target;
    _target = old;
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _modes.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dịch'),
          bottom: TabBar(
            tabs: [
              for (final (icon, label, _) in _modes)
                Tab(icon: Icon(icon), text: label),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: _LanguagePair(
                source: _source,
                target: _target,
                onSwap: _swap,
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final (icon, label, step) in _modes)
                    _ModePlaceholder(icon: icon, label: label, step: step),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguagePair extends StatelessWidget {
  const _LanguagePair({
    required this.source,
    required this.target,
    required this.onSwap,
  });

  final AppLanguage source;
  final AppLanguage target;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _LanguageBox(source, key: const Key('source-lang'))),
        IconButton(
          tooltip: 'Đổi chiều',
          onPressed: onSwap,
          icon: const Icon(Icons.swap_horiz_rounded),
        ),
        Expanded(child: _LanguageBox(target, key: const Key('target-lang'))),
      ],
    );
  }
}

class _LanguageBox extends StatelessWidget {
  const _LanguageBox(this.language, {super.key});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: AppSize.buttonHeightSmall,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        language.nativeName,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _ModePlaceholder extends StatelessWidget {
  const _ModePlaceholder({
    required this.icon,
    required this.label,
    required this.step,
  });

  final IconData icon;
  final String label;
  final String step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      children: [
        StepNotice('Chế độ $label: $step.'),
        const SizedBox(height: AppSpace.xxxl),
        Icon(icon, size: AppSize.avatarLg, color: theme.colorScheme.outline),
      ],
    );
  }
}
