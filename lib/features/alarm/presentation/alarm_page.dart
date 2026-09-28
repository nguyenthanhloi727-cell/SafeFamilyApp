import 'package:flutter/material.dart';

import '../../../core/constants/app_languages.dart';
import '../../../core/services/system_settings.dart';
import '../../../core/settings/voice_language_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/language_picker.dart';
import '../../../core/widgets/status_banner.dart';
import '../data/alarm_scheduler.dart';
import '../data/speech_recognizer.dart';
import '../domain/alarm_time.dart';
import 'alarm_controller.dart';
import 'alarm_samples.dart';
import 'widgets/alarm_confirm_card.dart';
import 'widgets/mic_button.dart';

/// S05 — Báo thức bằng giọng nói (mục 3): chọn ngôn ngữ → nói (hoặc gõ) →
/// xác nhận giờ → mở app Đồng hồ với giờ điền sẵn.
class AlarmPage extends StatefulWidget {
  const AlarmPage({
    super.key,
    this.recognizer,
    this.scheduler,
    this.systemSettings,
    this.clock,
  });

  final SpeechRecognizer? recognizer;
  final AlarmScheduler? scheduler;
  final SystemSettings? systemSettings;
  final DateTime Function()? clock;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  late final AlarmController _controller;
  late final SystemSettings _systemSettings;
  final _typed = TextEditingController();
  VoiceLanguageSettings? _settings;

  @override
  void initState() {
    super.initState();
    _systemSettings = widget.systemSettings ?? const AndroidSystemSettings();
    _controller = AlarmController(
      recognizer: widget.recognizer ?? SpeechToTextRecognizer(),
      scheduler: widget.scheduler ?? const AndroidAlarmScheduler(),
      // Cập nhật ngay trong didChangeDependencies theo cài đặt đã lưu.
      language: AppLanguage.defaultVoice,
      clock: widget.clock,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ngôn ngữ đổi ở màn Cài đặt → cập nhật ở đây (và ngược lại).
    _settings = VoiceLanguageScope.of(context);
    _controller.setLanguage(_settings!.language);
  }

  @override
  void dispose() {
    _typed.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickLanguage() async {
    final picked = await showLanguagePicker(
      context,
      selected: _controller.language,
      unavailable: _controller.unavailableLanguages,
    );
    if (picked != null) await _settings?.setLanguage(picked);
  }

  Future<void> _editTime(AlarmTime current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Chọn giờ báo thức',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      _controller.editTime(AlarmTime(picked.hour, picked.minute));
    }
  }

  void _submitTyped() {
    FocusScope.of(context).unfocus();
    _controller.submitText(_typed.text);
  }

  Future<void> _openSettings(Future<bool> Function() open) async {
    if (!await open() && mounted) {
      showAppSnackBar(context, 'Không mở được Cài đặt, hãy mở tay.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Báo thức')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final c = _controller;
    final sample = alarmSamplePhrases[c.language]!;
    final pending = c.pendingTime;

    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        Center(
          child: ActionChip(
            avatar: const Icon(Icons.language_rounded),
            label: Text('${c.language.nativeName}  ▾'),
            tooltip: 'Đổi ngôn ngữ giọng nói',
            onPressed: _pickLanguage,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (c.issue case final issue?) ...[
          _SpeechIssueBanner(
            issue: issue,
            languageName: c.language.vietnameseName,
            onOpenAppSettings: () =>
                _openSettings(_systemSettings.openAppSettings),
            onOpenVoiceSettings: () =>
                _openSettings(_systemSettings.openVoiceInputSettings),
            onRetry: c.toggleListening,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Text(
          'Hãy nói: “$sample”',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Center(
          child: MicButton(state: c.micState, onPressed: c.toggleListening),
        ),
        Text(
          switch (c.micState) {
            MicState.listening => 'Đang nghe… chạm để dừng',
            MicState.starting => 'Đang chuẩn bị micro…',
            MicState.idle => 'Chạm micro để nói',
          },
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge,
        ),
        if (c.transcript.isNotEmpty) ...[
          const SizedBox(height: AppSpace.lg),
          _TranscriptBox(text: c.transcript, live: c.isListening),
        ],
        if (c.notUnderstood) ...[
          const SizedBox(height: AppSpace.md),
          StatusBanner(
            type: StatusType.error,
            title: 'Không hiểu giờ',
            message:
                'Không tìm thấy giờ trong câu vừa rồi. Hãy nói rõ giờ, ví dụ: '
                '“$sample”. Nếu bạn đang nói ngôn ngữ khác, hãy đổi ngôn ngữ ở trên.',
          ),
        ],
        if (pending != null) ...[
          const SizedBox(height: AppSpace.md),
          AlarmConfirmCard(
            time: pending,
            now: c.now(),
            onSchedule: c.scheduleAlarm,
            onEdit: () => _editTime(pending),
          ),
        ],
        if (c.scheduledTime case final scheduled?) ...[
          const SizedBox(height: AppSpace.md),
          StatusBanner(
            type: StatusType.success,
            title: 'Đã mở app Đồng hồ',
            message:
                'Báo thức ${scheduled.format()} nhãn “${AlarmController.alarmLabel}”. '
                'Nếu app Đồng hồ hỏi lại, bấm Lưu để hoàn tất.',
          ),
        ],
        if (c.scheduleFailure != null && pending != null) ...[
          const SizedBox(height: AppSpace.md),
          StatusBanner(
            type: StatusType.error,
            title: c.scheduleFailure == AlarmScheduleResult.noClockApp
                ? 'Máy không có app Đồng hồ nhận lệnh đặt báo thức'
                : 'Không mở được app Đồng hồ',
            message:
                'Hãy mở app Đồng hồ và đặt báo thức tay lúc ${pending.format()}.',
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        const Divider(),
        const SizedBox(height: AppSpace.md),
        TextField(
          key: const Key('typed-command'),
          controller: _typed,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitTyped(),
          decoration: InputDecoration(
            labelText: 'Hoặc gõ câu lệnh',
            hintText: sample,
            helperText: 'Dùng khi micro lỗi — gõ giống như nói',
            suffixIcon: IconButton(
              tooltip: 'Hiểu giờ',
              onPressed: _submitTyped,
              icon: const Icon(Icons.send_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

class _TranscriptBox extends StatelessWidget {
  const _TranscriptBox({required this.text, required this.live});

  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            live ? 'Đang nghe:' : 'Bạn nói:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '“$text”',
            key: const Key('transcript'),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _SpeechIssueBanner extends StatelessWidget {
  const _SpeechIssueBanner({
    required this.issue,
    required this.languageName,
    required this.onOpenAppSettings,
    required this.onOpenVoiceSettings,
    required this.onRetry,
  });

  final SpeechIssue issue;
  final String languageName;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenVoiceSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = TextButton(onPressed: onRetry, child: const Text('Thử lại'));
    return switch (issue) {
      // S13 — Bị từ chối quyền.
      SpeechIssue.permissionDenied => StatusBanner(
        type: StatusType.error,
        title: 'Chưa có quyền dùng micro',
        message:
            'SafeFamily cần micro để nghe câu đặt giờ; âm thanh chỉ dùng để '
            'nhận giờ, không lưu lại. Vào Cài đặt → Quyền → Micro → Cho phép, '
            'rồi bấm Thử lại. Hoặc gõ câu lệnh ở cuối màn hình.',
        actions: [
          FilledButton(
            onPressed: onOpenAppSettings,
            child: const Text('Mở Cài đặt'),
          ),
          retry,
        ],
      ),
      SpeechIssue.serviceUnavailable => StatusBanner(
        type: StatusType.error,
        title: 'Máy không có dịch vụ nhận giọng nói',
        message:
            'Hãy cài hoặc bật app Google (dịch vụ nhận giọng nói của Google), '
            'rồi thử lại. Trong lúc đó có thể gõ câu lệnh ở cuối màn hình.',
        actions: [retry],
      ),
      SpeechIssue.languageUnavailable => StatusBanner(
        type: StatusType.warning,
        title: 'Máy chưa có gói nhận giọng nói $languageName',
        message:
            'Tải thêm: Cài đặt → Nhập bằng giọng nói (hoặc app Google → Cài đặt '
            '→ Giọng nói → Nhận dạng giọng nói ngoại tuyến) → thêm $languageName. '
            'Vẫn có thể thử nói khi có mạng, hoặc gõ câu lệnh.',
        actions: [
          OutlinedButton(
            onPressed: onOpenVoiceSettings,
            child: const Text('Mở cài đặt giọng nói'),
          ),
        ],
      ),
      SpeechIssue.noSpeech => const StatusBanner(
        type: StatusType.info,
        title: 'Không nghe rõ',
        message: 'Chạm micro và nói lại, gần máy hơn một chút.',
      ),
      SpeechIssue.network => const StatusBanner(
        type: StatusType.error,
        title: 'Cần kết nối mạng',
        message:
            'Máy đang nhận giọng nói qua mạng. Kiểm tra Wi-Fi/4G, '
            'hoặc tải gói ngôn ngữ ngoại tuyến.',
      ),
      SpeechIssue.other => StatusBanner(
        type: StatusType.error,
        title: 'Micro đang gặp lỗi',
        message: 'Thử lại, hoặc gõ câu lệnh ở cuối màn hình.',
        actions: [retry],
      ),
    };
  }
}
