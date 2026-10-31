import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/child_status_text.dart';
import '../../../core/theme/app_tokens.dart';

/// "Lệnh đã gửi": 50 lệnh gần nhất tới một máy con và trạng thái từng lệnh
/// (đang chờ / đã thực thi / quá hạn 24 giờ). Chỉ xem, không có thao tác nên không cần khóa phụ huynh.
class SentCommandsPage extends StatefulWidget {
  const SentCommandsPage({super.key, required this.device});

  final DeviceInfo device;

  @override
  State<SentCommandsPage> createState() => _SentCommandsPageState();
}

class _SentCommandsPageState extends State<SentCommandsPage> {
  List<CommandInfo>? _commands;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final api = ApiScope.of(context);
    try {
      final list = await api.getCommands(widget.device.id);
      if (mounted) {
        setState(() {
          _commands = list;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commands = _commands;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text('Lệnh đã gửi: ${widget.device.name}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (commands == null && _error == null)
              const LinearProgressIndicator(),
            if (commands != null && commands.isEmpty)
              const Text('Chưa gửi lệnh nào.'),
            for (final c in commands ?? const <CommandInfo>[])
              _CommandTile(command: c, state: c.stateAt(now), now: now),
            if (commands != null && commands.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.md),
                child: Text(
                  'Máy con nhận lệnh ở lần đồng bộ kế (tối đa vài phút). Lệnh chưa nhận sau 24 giờ sẽ không được giao nữa.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    required this.command,
    required this.state,
    required this.now,
  });

  final CommandInfo command;
  final CommandState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (state) {
      CommandState.pending => (
        Icons.hourglass_top_rounded,
        'Đang chờ máy con',
        scheme.secondary,
      ),
      CommandState.done => (
        Icons.check_circle_rounded,
        'Đã thực thi ${agoText(command.doneAt!, now)}',
        scheme.primary,
      ),
      CommandState.expired => (
        Icons.timer_off_rounded,
        'Quá hạn 24 giờ, không giao nữa',
        scheme.error,
      ),
    };
    return ListTile(
      key: Key('command-${command.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(commandLabel(command)),
      subtitle: Text('Gửi ${agoText(command.createdAt, now)} · $label'),
    );
  }
}
