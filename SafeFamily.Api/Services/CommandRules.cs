using System.Text.Json;

namespace SafeFamily.Api.Services;

/// <summary>
/// Danh sách loại lệnh mẹ được gửi và kiểm tra payload. Máy con (FamilySync.apply) vẫn tự kiểm
/// lại, vì server chỉ là lớp chặn sớm. Lệnh chưa giao sau <see cref="MaxAge"/> thì không giao nữa.
/// </summary>
public static class CommandRules
{
    public const int MaxPayloadBytes = 4 * 1024;
    public static readonly TimeSpan MaxAge = TimeSpan.FromHours(24);

    /// <summary>Mở tạm một app: 1 phút đến 4 giờ (khớp FamilySync.MAX_UNLOCK_MINUTES).</summary>
    public const int MaxUnlockMinutes = 240;
    const int MaxPauseMinutes = 24 * 60; // khớp TimeLimits.MAX_PAUSE_MINUTES

    static readonly HashSet<string> NoPayload =
        ["unpause", "unlock", "study_stop", "disable_limit_today", "enable_limit_today", "study_approve", "study_reject"];

    static readonly HashSet<string> WithMinutes = ["pause", "lock", "study_start"];

    static readonly HashSet<string> WithPackage = ["app_relock", "app_block", "app_allow"];

    public const string UnlockTemp = "app_unlock_temp";

    /// <summary>Trả về thông báo lỗi, hoặc null nếu hợp lệ.</summary>
    public static string? Validate(string type, string payloadJson)
    {
        var known = NoPayload.Contains(type) || WithMinutes.Contains(type) || WithPackage.Contains(type) || type == UnlockTemp;
        if (!known) return "Loại lệnh không hợp lệ.";
        if (System.Text.Encoding.UTF8.GetByteCount(payloadJson) > MaxPayloadBytes) return "Payload quá lớn.";
        JsonElement root;
        try
        {
            using var doc = JsonDocument.Parse(payloadJson);
            root = doc.RootElement.Clone();
        }
        catch (JsonException) { return "Payload không phải JSON hợp lệ."; }
        if (root.ValueKind != JsonValueKind.Object) return "Payload phải là một đối tượng JSON.";

        if (NoPayload.Contains(type)) return null;
        if (WithMinutes.Contains(type))
        {
            // minutes là tùy chọn (pause/lock/study_start có mặc định ở máy con); 0 = đến khi tắt, chỉ với pause.
            if (!root.TryGetProperty("minutes", out var m)) return null;
            if (!TryInt(m, out var minutes)) return "minutes phải là số nguyên.";
            var min = type == "pause" ? 0 : 1;
            return minutes >= min && minutes <= MaxPauseMinutes ? null : "minutes ngoài khoảng cho phép.";
        }
        if (!TryPackage(root, out _)) return "Thiếu hoặc sai package.";
        if (type != UnlockTemp) return null;
        if (!root.TryGetProperty("minutes", out var um) || !TryInt(um, out var u)) return "Thiếu minutes (số nguyên).";
        return u is >= 1 and <= MaxUnlockMinutes ? null : $"minutes phải từ 1 đến {MaxUnlockMinutes}.";
    }

    static bool TryInt(JsonElement e, out int value)
    {
        value = 0;
        return e.ValueKind == JsonValueKind.Number && e.TryGetInt32(out value);
    }

    /// <summary>Tên gói Android: các đoạn chữ/số/gạch dưới ngăn bởi dấu chấm, tối đa 200 ký tự.</summary>
    static bool TryPackage(JsonElement root, out string package)
    {
        package = "";
        if (!root.TryGetProperty("package", out var p) || p.ValueKind != JsonValueKind.String) return false;
        package = p.GetString() ?? "";
        return package.Length is > 0 and <= 200 &&
               System.Text.RegularExpressions.Regex.IsMatch(package, @"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$");
    }
}
