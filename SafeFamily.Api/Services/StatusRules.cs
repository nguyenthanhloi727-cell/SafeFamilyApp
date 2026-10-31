using System.Text.Json;
using System.Text.RegularExpressions;
using SafeFamily.Api.Dtos;

namespace SafeFamily.Api.Services;

/// <summary>Kiểm tra và chuẩn hóa trạng thái máy con gửi lên (API-09): kiểu, số lượng, độ dài từng trường.</summary>
public static partial class StatusRules
{
    public const int MaxPermissions = 20;
    public const int MaxPermissionLength = 40;
    public const int MaxTempUnlocked = 50;
    /// <summary>Đủ cho 50 gói × (200 ký tự + giờ) và 20 id quyền; cột DB cũng giới hạn theo số này.</summary>
    public const int MaxListJsonChars = 16 * 1024;
    /// <summary>Hạn mở tạm xa nhất hợp lệ: khớp CommandRules.MaxUnlockMinutes, cộng dư 5 phút lệch đồng hồ.</summary>
    static readonly TimeSpan MaxUntilAhead = TimeSpan.FromMinutes(CommandRules.MaxUnlockMinutes + 5);

    [GeneratedRegex(@"^[a-z][a-z0-9_]*$")]
    private static partial Regex PermissionId();

    [GeneratedRegex(@"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$")]
    private static partial Regex PackageName();

    [GeneratedRegex(@"^[0-9A-Za-z.+_-]+$")]
    private static partial Regex Version();

    /// <summary>Trả về lỗi (tiếng Việt) hoặc null nếu hợp lệ. <paramref name="now"/> để test cố định giờ.</summary>
    public static string? Validate(PutStatusRequest r, DateTime now)
    {
        if (r.AppVersion is { Length: > 0 } v && !Version().IsMatch(v)) return "appVersion không hợp lệ.";
        var perms = r.PermissionsMissing ?? [];
        if (perms.Count > MaxPermissions) return "Quá nhiều quyền.";
        if (perms.Any(p => p is null || p.Length > MaxPermissionLength || !PermissionId().IsMatch(p)))
            return "Mã quyền không hợp lệ.";
        var temp = r.TempUnlocked ?? [];
        if (temp.Count > MaxTempUnlocked) return "Quá nhiều app mở tạm.";
        if (temp.Any(t => t is null || !PackageName().IsMatch(t.Package ?? "") || t.Package!.Length > 200))
            return "Tên gói không hợp lệ.";
        if (temp.Any(t => t.Until == default)) return "Thiếu hạn mở tạm.";
        // Hạn không thể ở xa quá thời gian mở tạm tối đa: chặn giá trị rác làm nút "chặn lại" hiện mãi.
        if (temp.Any(t => t.Until.ToUniversalTime() > now + MaxUntilAhead)) return "Hạn mở tạm không hợp lệ.";
        return null;
    }

    public static string ToJson<T>(IEnumerable<T> items) => JsonSerializer.Serialize(items);

    public static List<string> ParsePermissions(string json) => Parse<string>(json);

    public static List<TempUnlockItem> ParseTempUnlocked(string json) => Parse<TempUnlockItem>(json);

    static List<T> Parse<T>(string json)
    {
        try { return JsonSerializer.Deserialize<List<T>>(json) ?? []; }
        catch (JsonException) { return []; }
    }
}
