import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/constants/app_languages.dart';

enum SpeechInitStatus {
  ready,

  /// Người dùng từ chối quyền micro.
  permissionDenied,

  /// Máy không có dịch vụ nhận giọng nói.
  unavailable,
}

/// Lỗi trong lúc nghe, đã gom lại theo cách xử lý trên giao diện.
enum SpeechError {
  /// Không nghe thấy / không nhận ra câu nào.
  noSpeech,

  /// Máy chưa có gói ngôn ngữ đang chọn.
  languageUnavailable,

  /// Cần mạng (nhận giọng nói qua máy chủ).
  network,

  permissionDenied,
  other,
}

/// Nhận giọng nói. Bản thật dùng speech_to_text; test dùng bản giả.
abstract interface class SpeechRecognizer {
  /// Gọi lần đầu sẽ xin quyền micro.
  Future<SpeechInitStatus> initialize();

  /// Mã locale máy hỗ trợ ("vi-VN", "en_US"…). Rỗng = máy không cho biết.
  Future<List<String>> supportedLocaleIds();

  Future<void> listen({
    required AppLanguage language,
    required void Function(String words, bool isFinal) onResult,
    required void Function() onDone,
    required void Function(SpeechError error) onError,
  });

  Future<void> stop();
  Future<void> cancel();
}

/// `true` nếu [localeIds] có [language] ("vi_VN", "vi-VN", "vi"…).
/// Danh sách rỗng (máy không báo) → coi như có, để vẫn cho thử.
bool isLanguageSupported(List<String> localeIds, AppLanguage language) {
  if (localeIds.isEmpty) return true;
  return localeIds.any((id) {
    final code = id.replaceAll('_', '-').split('-').first.toLowerCase();
    return language.languageCodes.contains(code);
  });
}

class SpeechToTextRecognizer implements SpeechRecognizer {
  SpeechToTextRecognizer({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;

  // Callback của lượt nghe hiện tại (speech_to_text chỉ nhận listener lúc initialize).
  void Function()? _onDone;
  void Function(SpeechError)? _onError;

  @override
  Future<SpeechInitStatus> initialize() async {
    if (_initialized) return SpeechInitStatus.ready;
    final ok = await _speech.initialize(
      onError: _handleError,
      onStatus: _handleStatus,
    );
    if (ok) {
      _initialized = true;
      return SpeechInitStatus.ready;
    }
    return await _speech.hasPermission
        ? SpeechInitStatus.unavailable
        : SpeechInitStatus.permissionDenied;
  }

  @override
  Future<List<String>> supportedLocaleIds() async {
    try {
      return [for (final l in await _speech.locales()) l.localeId];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> listen({
    required AppLanguage language,
    required void Function(String words, bool isFinal) onResult,
    required void Function() onDone,
    required void Function(SpeechError error) onError,
  }) async {
    _onDone = onDone;
    _onError = onError;
    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: language.localeTag,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  void _handleStatus(String status) {
    if (status == SpeechToText.doneStatus) {
      final onDone = _onDone;
      _onDone = null;
      onDone?.call();
    }
  }

  void _handleError(SpeechRecognitionError error) {
    final onError = _onError;
    if (onError == null) return;
    onError(switch (error.errorMsg) {
      'error_no_match' || 'error_speech_timeout' => SpeechError.noSpeech,
      'error_language_not_supported' ||
      'error_language_unavailable' => SpeechError.languageUnavailable,
      'error_network' ||
      'error_network_timeout' ||
      'error_server' ||
      'error_server_disconnected' => SpeechError.network,
      'error_permission' => SpeechError.permissionDenied,
      _ => SpeechError.other,
    });
  }
}
