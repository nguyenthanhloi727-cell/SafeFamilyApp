/// 5 ngôn ngữ dùng chung cho Dịch và giọng nói Báo thức (DESIGN.md mục 6, C8).
///
/// Dart thuần (không import Flutter) để lớp domain dùng được.
enum AppLanguage {
  vietnamese('vi-VN', 'Tiếng Việt', 'tiếng Việt', ['vi']),
  english('en-US', 'English', 'tiếng Anh', ['en']),
  japanese('ja-JP', '日本語', 'tiếng Nhật', ['ja']),
  chinese('zh-CN', '中文', 'tiếng Trung', ['zh', 'cmn']),
  korean('ko-KR', '한국어', 'tiếng Hàn', ['ko']);

  const AppLanguage(
    this.localeTag,
    this.nativeName,
    this.vietnameseName,
    this.languageCodes,
  );

  /// Mã BCP-47 gửi cho bộ nhận giọng nói, ví dụ "vi-VN".
  final String localeTag;

  /// Tên theo chính ngôn ngữ đó: "日本語".
  final String nativeName;

  /// Tên tiếng Việt, viết thường để ghép câu: "tiếng Nhật".
  final String vietnameseName;

  /// Mã ngôn ngữ (phần đầu của locale) được coi là cùng ngôn ngữ này.
  final List<String> languageCodes;

  /// Ngôn ngữ giọng nói mặc định (DESIGN.md mục 8).
  static const defaultVoice = AppLanguage.vietnamese;

  static AppLanguage fromLocaleTag(String? tag) => AppLanguage.values
      .firstWhere((l) => l.localeTag == tag, orElse: () => defaultVoice);
}
