import 'package:flutter/foundation.dart';

import '../../../core/constants/app_languages.dart';
import '../data/alarm_scheduler.dart';
import '../data/speech_recognizer.dart';
import '../domain/alarm_time.dart';
import '../domain/time_parser.dart';

enum MicState { idle, starting, listening }

/// Vấn đề về micro / nhận giọng nói cần báo cho người dùng.
enum SpeechIssue {
  permissionDenied,
  serviceUnavailable,
  languageUnavailable,
  noSpeech,
  network,
  other,
}

/// State màn Báo thức: nghe → hiểu giờ → xác nhận → đặt vào app Đồng hồ.
class AlarmController extends ChangeNotifier {
  AlarmController({
    required this._recognizer,
    required this._scheduler,
    required this._language,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const alarmLabel = 'SafeFamily';

  final SpeechRecognizer _recognizer;
  final AlarmScheduler _scheduler;
  final DateTime Function() _clock;

  AppLanguage _language;
  bool _initialized = false;
  List<String> _supportedLocales = const [];

  MicState _micState = MicState.idle;
  SpeechIssue? _issue;
  String _transcript = '';
  AlarmTime? _pendingTime;
  bool _notUnderstood = false;
  AlarmTime? _scheduledTime;
  AlarmScheduleResult? _scheduleFailure;
  bool _disposed = false;

  AppLanguage get language => _language;
  MicState get micState => _micState;
  bool get isListening => _micState == MicState.listening;
  SpeechIssue? get issue => _issue;

  /// Câu nhận được (hiện theo thời gian thực khi đang nói).
  String get transcript => _transcript;

  /// Giờ đã hiểu, chờ người dùng xác nhận.
  AlarmTime? get pendingTime => _pendingTime;
  bool get notUnderstood => _notUnderstood;

  /// Giờ vừa gửi sang app Đồng hồ thành công.
  AlarmTime? get scheduledTime => _scheduledTime;

  /// Lần "Đặt báo thức" gần nhất không mở được app Đồng hồ.
  AlarmScheduleResult? get scheduleFailure => _scheduleFailure;

  DateTime now() => _clock();

  /// Ngôn ngữ đã biết là máy chưa có gói nhận giọng nói.
  Set<AppLanguage> get unavailableLanguages => {
    for (final l in AppLanguage.values)
      if (!isLanguageSupported(_supportedLocales, l)) l,
  };

  void setLanguage(AppLanguage language) {
    if (language == _language) return;
    if (isListening) _recognizer.cancel();
    _language = language;
    _micState = MicState.idle;
    _resetResult();
    _issue = _initialized && !isLanguageSupported(_supportedLocales, language)
        ? SpeechIssue.languageUnavailable
        : null;
    _notify();
  }

  /// Bấm micro: bắt đầu nghe, hoặc dừng nếu đang nghe.
  Future<void> toggleListening() async {
    if (_micState == MicState.starting) return;
    if (isListening) {
      await _recognizer.stop();
      return;
    }

    _micState = MicState.starting;
    _issue = null;
    _resetResult();
    _notify();

    if (!_initialized) {
      final status = await _recognizer.initialize();
      if (status != SpeechInitStatus.ready) {
        _micState = MicState.idle;
        _issue = status == SpeechInitStatus.permissionDenied
            ? SpeechIssue.permissionDenied
            : SpeechIssue.serviceUnavailable;
        _notify();
        return;
      }
      _initialized = true;
      _supportedLocales = await _recognizer.supportedLocaleIds();
    }

    if (!isLanguageSupported(_supportedLocales, _language)) {
      // Vẫn cho thử (máy có thể nhận qua mạng) nhưng báo trước.
      _issue = SpeechIssue.languageUnavailable;
    }

    _micState = MicState.listening;
    _notify();
    try {
      await _recognizer.listen(
        language: _language,
        onResult: _onResult,
        onDone: _onDone,
        onError: _onError,
      );
    } catch (_) {
      _micState = MicState.idle;
      _issue = SpeechIssue.other;
      _notify();
    }
  }

  /// Ô gõ tay: dự phòng khi micro lỗi, và để demo.
  void submitText(String text) {
    if (isListening) _recognizer.cancel();
    _micState = MicState.idle;
    _resetResult();
    _transcript = text.trim();
    _interpret();
  }

  /// "Sửa giờ" từ bộ chọn giờ.
  void editTime(AlarmTime time) {
    _pendingTime = time;
    _notUnderstood = false;
    _scheduledTime = null;
    _scheduleFailure = null;
    _notify();
  }

  /// "Đặt báo thức": mở app Đồng hồ với giờ điền sẵn.
  Future<AlarmScheduleResult> scheduleAlarm() async {
    final time = _pendingTime;
    if (time == null) return AlarmScheduleResult.failed;
    final result = await _scheduler.setAlarm(time, label: alarmLabel);
    final opened = result == AlarmScheduleResult.opened;
    _scheduledTime = opened ? time : null;
    _scheduleFailure = opened ? null : result;
    _notify();
    return result;
  }

  void _onResult(String words, bool isFinal) {
    _transcript = words;
    if (isFinal) {
      _micState = MicState.idle;
      _interpret();
    } else {
      _notify();
    }
  }

  void _onDone() {
    if (!isListening) return; // đã có kết quả cuối
    _micState = MicState.idle;
    if (_transcript.isEmpty) {
      _issue ??= SpeechIssue.noSpeech;
      _notify();
    } else {
      _interpret();
    }
  }

  void _onError(SpeechError error) {
    _micState = MicState.idle;
    _issue = switch (error) {
      SpeechError.noSpeech => SpeechIssue.noSpeech,
      SpeechError.languageUnavailable => SpeechIssue.languageUnavailable,
      SpeechError.network => SpeechIssue.network,
      SpeechError.permissionDenied => SpeechIssue.permissionDenied,
      SpeechError.other => SpeechIssue.other,
    };
    _notify();
  }

  void _interpret() {
    if (_transcript.isEmpty) {
      _notify();
      return;
    }
    switch (parseAlarmTime(_transcript, _language, now: _clock())) {
      case TimeUnderstood(:final time):
        _pendingTime = time;
        _notUnderstood = false;
        if (_issue == SpeechIssue.noSpeech) _issue = null;
      case TimeNotUnderstood():
        _pendingTime = null;
        _notUnderstood = true;
    }
    _notify();
  }

  void _resetResult() {
    _transcript = '';
    _pendingTime = null;
    _notUnderstood = false;
    _scheduledTime = null;
    _scheduleFailure = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (isListening) _recognizer.cancel();
    super.dispose();
  }
}
