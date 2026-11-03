using System.Text.Json;
using System.Text.RegularExpressions;

namespace SafeFamily.Api.Services;

/// <summary>
/// Kiểm tra phần server hiểu trong gói luật (API-13). Phần còn lại của gói (timeLimit, appLock...) vẫn lưu nguyên khối.
/// <c>contacts</c> = danh bạ của con mẹ đặt (schema 3, T10): tối đa <see cref="MaxContacts"/> mục, trong đó
/// tối đa <see cref="MaxSos"/> mục <c>sos:true</c>; mỗi mục <c>{"label":string 1–30,"phone":"+?9–12 chữ số","sos":bool tùy chọn}</c>.
/// Thiếu <c>sos</c>: gói <c>schemaVersion</c> &lt; 3 coi là true (schema 2 chỉ chứa số SOS), gói từ 3 coi là false.
/// </summary>
public static partial class PolicyRules
{
    public const int MaxContacts = 20;
    public const int MaxSos = 3;
    public const int MaxLabelLength = 30;

    [GeneratedRegex(@"^\+?[0-9]{9,12}$")]
    private static partial Regex PhonePattern();

    /// <summary>Trả câu báo lỗi (cho 400) hoặc null nếu hợp lệ. <paramref name="root"/> đã là đối tượng JSON.</summary>
    public static string? Validate(JsonElement root)
    {
        if (!root.TryGetProperty("contacts", out var contacts)) return null;
        if (contacts.ValueKind != JsonValueKind.Array) return "contacts phải là một mảng.";
        if (contacts.GetArrayLength() > MaxContacts) return $"contacts tối đa {MaxContacts} số.";
        var schema = root.TryGetProperty("schemaVersion", out var sv) && sv.ValueKind == JsonValueKind.Number &&
                     sv.TryGetInt32(out var n) ? n : 1;
        var sosCount = 0;
        foreach (var c in contacts.EnumerateArray())
        {
            if (c.ValueKind != JsonValueKind.Object) return "Mỗi mục contacts phải là một đối tượng.";
            if (!c.TryGetProperty("label", out var label) || label.ValueKind != JsonValueKind.String ||
                !LabelOk(label.GetString()))
                return $"Nhãn liên hệ phải là chuỗi 1–{MaxLabelLength} ký tự, không có ký tự điều khiển.";
            if (!c.TryGetProperty("phone", out var phone) || phone.ValueKind != JsonValueKind.String ||
                !PhonePattern().IsMatch(phone.GetString() ?? ""))
                return "Số điện thoại phải gồm 9–12 chữ số, có thể có dấu + ở đầu.";
            if (c.TryGetProperty("sos", out var sos) && sos.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                return "sos phải là true/false.";
            var isSos = c.TryGetProperty("sos", out var flag) ? flag.ValueKind == JsonValueKind.True : schema < 3;
            if (isSos && ++sosCount > MaxSos) return $"Tối đa {MaxSos} số SOS (sos:true).";
        }
        return null;
    }

    static bool LabelOk(string? s)
    {
        var t = s?.Trim();
        return !string.IsNullOrEmpty(t) && t.Length <= MaxLabelLength && !t.Any(char.IsControl);
    }
}
