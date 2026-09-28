import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/security/unlock_log.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/confirm_delete_dialog.dart';

/// S18 — Nhật ký mở khóa: thời gian, thao tác, phương thức, kết quả.
class UnlockLogPage extends StatefulWidget {
  const UnlockLogPage({super.key});

  @override
  State<UnlockLogPage> createState() => _UnlockLogPageState();
}

class _UnlockLogPageState extends State<UnlockLogPage> {
  Future<List<UnlockLogEntry>>? _entries;
  ParentGuard? _guard;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Guard báo thay đổi (vừa ghi thêm / vừa xóa) → đọc lại.
    _guard = ParentGuardScope.maybeOf(context);
    _entries = _guard?.log.entries();
  }

  Future<void> _clear() async {
    final guard = _guard;
    if (guard == null) return;
    final prompt = ParentGate.promptFor(context);
    final confirmed = await confirmDelete(
      context,
      title: 'Xóa nhật ký mở khóa?',
      message: 'Toàn bộ lịch sử mở khóa sẽ bị xóa. Cần xác thực phụ huynh.',
    );
    if (confirmed) await guard.clearLog(promptPin: prompt);
  }

  @override
  Widget build(BuildContext context) {
    return ParentAreaGuard(child: _buildPage(context));
  }

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký mở khóa'),
        actions: [
          IconButton(
            tooltip: 'Xóa nhật ký',
            onPressed: _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<UnlockLogEntry>>(
        future: _entries,
        builder: (context, snapshot) {
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entries.isEmpty) {
            return const Center(child: Text('Chưa có lần mở khóa nào.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            itemCount: entries.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == entries.length) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(
                    'Lưu tối đa ${UnlockLog.maxEntries} lần gần nhất, chỉ trên máy này.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              return _EntryTile(entry: entries[index]);
            },
          );
        },
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final UnlockLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = theme.extension<AppColors>()!;
    final (IconData icon, Color color) = switch (entry.result) {
      UnlockResult.success => (Icons.check_circle_rounded, app.success),
      UnlockResult.failure => (Icons.cancel_rounded, theme.colorScheme.error),
      UnlockResult.canceled => (
        Icons.remove_circle_outline_rounded,
        theme.colorScheme.outline,
      ),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(entry.action),
      subtitle: Text(
        '${formatDateTime(entry.time)} · ${entry.method.label} · '
        '${entry.result.label}',
      ),
    );
  }
}

/// "14:05:09 28/09/2026"
String formatDateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)} '
      '${two(t.day)}/${two(t.month)}/${t.year}';
}
