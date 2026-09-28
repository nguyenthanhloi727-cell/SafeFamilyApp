/// 5 ngôn ngữ dùng chung cho Dịch và giọng nói Báo thức (DESIGN.md mục 6, C8).
enum AppLanguage {
  vietnamese('vi-VN', 'Tiếng Việt'),
  english('en-US', 'English'),
  japanese('ja-JP', '日本語'),
  chinese('zh-CN', '中文'),
  korean('ko-KR', '한국어');

  const AppLanguage(this.localeTag, this.nativeName);

  final String localeTag;
  final String nativeName;

  /// Ngôn ngữ giọng nói mặc định (DESIGN.md mục 8).
  static const defaultVoice = AppLanguage.vietnamese;
}
