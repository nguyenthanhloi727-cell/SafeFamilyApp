import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Trạng thái màn chặn giờ học (native giữ, lưu bền):
/// `studying → childClaimsDone → approved | rejected`.
enum StudyBlockState {
  studying('studying'),
  childClaimsDone('child_claims_done'),
  approved('approved'),
  rejected('rejected');

  const StudyBlockState(this.wire);

  final String wire;

  static StudyBlockState parse(String? value) => StudyBlockState.values
      .firstWhere((s) => s.wire == value, orElse: () => studying);
}

/// Phụ huynh duyệt "Đã học xong" của con (kênh `safefamily/study`).
abstract interface class StudyApprovalPlatform {
  Future<StudyBlockState> state();

  /// Chỉ gọi sau khi đã xác thực phụ huynh. `false` nếu con chưa báo xong.
  Future<bool> approve();

  /// Quay lại học. `false` nếu con chưa báo xong.
  Future<bool> reject();
}

class MethodChannelStudyApproval implements StudyApprovalPlatform {
  const MethodChannelStudyApproval();

  static const _channel = MethodChannel('safefamily/study');

  @override
  Future<StudyBlockState> state() async {
    try {
      return StudyBlockState.parse(
        await _channel.invokeMethod<String>('state'),
      );
    } on PlatformException catch (error) {
      debugPrint('Giờ học: không đọc được trạng thái ($error)');
      return StudyBlockState.studying;
    } on MissingPluginException {
      return StudyBlockState.studying;
    }
  }

  @override
  Future<bool> approve() async =>
      await _channel.invokeMethod<bool>('approve') ?? false;

  @override
  Future<bool> reject() async =>
      await _channel.invokeMethod<bool>('reject') ?? false;
}
