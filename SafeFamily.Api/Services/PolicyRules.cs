using System.Text.Json;
using System.Text.RegularExpressions;

namespace SafeFamily.Api.Services;

/// <summary>
/// Kiểm tra phần server hiểu trong gói luật (API-13). Phần còn lại của gói (timeLimit, appLock...) vẫn lưu nguyên khối.
/// <c>contacts</c> = số khẩn cấp SOS do mẹ chọn, KHÔNG phải cả danh bạ: tối đa <see cref="MaxContacts"/> mục,
/// mỗi mục <c>{"label":string 1–30,"phone":"+?9–12 chữ số","sos":bool tùy chọn}</c>.
/// </summary>
public static partial class PolicyRules
{
    public const int MaxContacts = 3;
    public const int MaxLabelLength = 30;

    [GeneratedRegex(@"^\+?[0-9]{9,12}$")]
    private static partial Regex PhonePattern();

    /// <summary>Trả câu báo lỗi (cho 400) hoặc null nếu hợp lệ. <paramref name="root"/> đã là đối tượng JSON.</summary>
    public static string? Validate(JsonElement root)
    {
        if (!root.TryGetProperty("contacts", out var contacts)) return null;
        if (contacts.ValueKind != JsonValueKind.Array) return "contacts phải là một mảng.";
        if (contacts.GetArrayLength() > MaxContacts) return $"contacts tối đa {MaxContacts} số.";
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
        }
        return null;
    }

    static bool LabelOk(string? s)
    {
        var t = s?.Trim();
        return !string.IsNullOrEmpty(t) && t.Length <= MaxLabelLength && !t.Any(char.IsControl);
    }
}
