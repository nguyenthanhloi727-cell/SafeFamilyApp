import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/step_notice.dart';
import '../data/team_members.dart';

/// S11 — Nhóm: thẻ thành viên lướt ngang (giữ chỗ).
class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final _controller = PageController(viewportFraction: 0.85);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nhóm')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: StepNotice('Thẻ thành viên đầy đủ: sẽ làm ở bước 4.'),
          ),
          const SizedBox(height: AppSpace.lg),
          SizedBox(
            height: AppSize.memberCardHeight,
            child: PageView.builder(
              controller: _controller,
              itemCount: teamMembers.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                child: _MemberCard(teamMembers[index]),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          _PageDots(count: teamMembers.length, current: _page),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard(this.member);

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          children: [
            CircleAvatar(
              radius: AppSize.avatarLg / 2,
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundColor: scheme.onSurfaceVariant,
              child: const Icon(Icons.person_rounded, size: AppSize.avatarMd),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              member.fullName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpace.md),
            _Field('MSSV', member.studentId),
            _Field('Email', member.email),
            _Field('Vai trò', member.role),
            _Field('Lớp', member.className),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 32),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(value ?? '', style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
      ],
    );
  }
}
