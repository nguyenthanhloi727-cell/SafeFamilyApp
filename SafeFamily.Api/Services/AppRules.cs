using SafeFamily.Api.Dtos;

namespace SafeFamily.Api.Services;

/// <summary>
/// Quy tắc duyệt app mới cài (API-07). Server chỉ giữ tên + tên gói + trạng thái duyệt. Máy con chỉ có thể báo
/// "app mới" (IsNew), không tự đặt allowed/blocked; chỉ mẹ (PUT) mới quyết định.
/// </summary>
public static class AppRules
{
    public const string New = "new";
    public const string Allowed = "allowed";
    public const string Blocked = "blocked";

    /// <summary>Số app tối đa lưu cho một máy: chặn máy con làm đầy bảng.</summary>
    public const int MaxAppsPerDevice = 2000;
    public const int MaxPostItems = 2000;
    public const int MaxLabelLength = 200;
    /// <summary>Số dòng tối đa mẹ nhận trong một lần GET.</summary>
    public const int MaxListRows = 200;
    /// <summary>Số quyết định tối đa máy con kéo trong một lần.</summary>
    public const int MaxDecisionRows = 500;

    public static bool IsStatus(string? s) => s is New or Allowed or Blocked;

    /// <summary>Mẹ chỉ được đặt allowed hoặc blocked.</summary>
    public static bool IsDecision(string? s) => s is Allowed or Blocked;

    /// <summary>Trả về lỗi hoặc null. Kiểm từng phần tử: tên gói đúng dạng, nhãn không rỗng/không ký tự điều khiển.</summary>
    public static string? Validate(PostAppsRequest r)
    {
        if (r.Apps.Count > MaxPostItems) return "Quá nhiều app.";
        foreach (var a in r.Apps)
        {
            if (a is null) return "App không hợp lệ.";
            if (!CommandRules.IsPackage(a.PackageName)) return "Tên gói không hợp lệ.";
            if (a.Label is null || a.Label.Length > MaxLabelLength) return "Tên app quá dài.";
        }
        return null;
    }

    /// <summary>Bỏ ký tự điều khiển và khoảng trắng thừa; rỗng thì dùng tên gói.</summary>
    public static string CleanLabel(string label, string package)
    {
        var cleaned = new string(label.Where(c => !char.IsControl(c)).ToArray()).Trim();
        return cleaned.Length == 0 ? package : cleaned;
    }
}
