import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../core/network/child_status_text.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';

/// "Yêu cầu của con": việc đang chờ mẹ duyệt (xin thêm giờ, "đã học xong") và vài yêu cầu gần đây đã xử lý.
/// Duyệt và từ chối ĐỀU qua khóa phụ huynh (`ParentGate.always`, vân tay hoặc PIN). Server tự tạo lệnh
/// cho máy con; con thấy kết quả ở lần đồng bộ kế (tối đa vài phút).
class ChildRequestsPage extends StatefulWidget {
  const ChildRequestsPage({super.key, required this.device});

  final DeviceInfo device;

  @override
  State<ChildRequestsPage> createState() => _ChildRequestsPageState();
}

class _ChildRequestsPageState extends State<ChildRequestsPage> {
  List<ChildRequestInfo>? _requests;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final api = ApiScope.of(context);
    try {
      final list = await api.getRequests(widget.device.id);
      if (mounted) {
        setState(() {
          _requests = list;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(ChildRequestInfo r, {required bool approve}) async {
    if (_busy) return;
    final api = ApiScope.of(context);
    final what = '${approve ? 'Duyệt' : 'Từ chối'}: ${requestLabel(r)}';
    if (!await ParentGate.always(context, what)) return;
    setState(() => _busy = true);
    try {
      await api.decideRequest(
        r.id,
        approve: approve,
        minutes: approve && r.kind == RequestKind.extraTime
            ? r.approveMinutes
            : null,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          approve
              ? 'Đã duyệt. Máy con nhận ở lần đồng bộ kế (tối đa vài phút).'
              : 'Đã từ chối.',
        );
      }
    } on ApiException catch (e) {
      // 409: đã xử lý ở nơi khác hoặc hết hạn. Tải lại cho mẹ thấy trạng thái thật.
      if (mounted) showAppSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requests = _requests;
    final pending = [
      for (final r in requests ?? const <ChildRequestInfo>[])
        if (r.isPending) r,
    ];
    final recent = [
      for (final r in requests ?? const <ChildRequestInfo>[])
        if (!r.isPending) r,
    ];
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text('Yêu cầu của ${widget.device.name}')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (requests == null && _error == null)
              const LinearProgressIndicator(),
            if (requests != null && pending.isEmpty)
              const Text('Không có yêu cầu nào đang chờ.'),
            for (final r in pending)
              Card(
                key: Key('request-${r.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(requestLabel(r), style: theme.textTheme.titleMedium),
                      Text(
                        'Gửi ${agoText(r.createdAt, now)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Row(
                        children: [
                          FilledButton(
                            key: Key('approve-${r.id}'),
                            onPressed: _busy
                                ? null
                                : () => _decide(r, approve: true),
                            child: Text(
                              r.kind == RequestKind.extraTime
                                  ? 'Duyệt ${r.approveMinutes} phút'
                                  : 'Duyệt',
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          OutlinedButton(
                            key: Key('reject-${r.id}'),
                            onPressed: _busy
                                ? null
                                : () => _decide(r, approve: false),
                            child: Text(
                              r.kind == RequestKind.studyDone
                                  ? 'Học tiếp'
                                  : 'Từ chối',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              Text('Đã xử lý gần đây', style: theme.textTheme.titleSmall),
              for (final r in recent.take(10))
                ListTile(
                  key: Key('done-${r.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    r.status == 'approved'
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: r.status == 'approved'
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  title: Text(requestLabel(r)),
                  subtitle: Text(
                    '${r.status == 'approved' ? 'Đã duyệt' : 'Đã từ chối'} '
                    '${agoText(r.decidedAt ?? r.createdAt, now)}',
                  ),
                ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Text(
                'Yêu cầu chờ quá 24 giờ sẽ hết hạn. Con chỉ gửi loại yêu cầu và số phút xin, không gửi app đang dùng.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
