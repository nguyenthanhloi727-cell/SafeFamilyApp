namespace SafeFamily.Api.Services;

/// <summary>Quy tắc tên máy con (API-01).</summary>
public static class DeviceRules
{
    public const int MaxNameLength = 50;

    /// <summary>Cắt khoảng trắng hai đầu; rỗng, quá dài hoặc có ký tự điều khiển (xuống dòng, tab, NUL...) → null.</summary>
    public static string? CleanName(string? name)
    {
        var s = name?.Trim();
        if (string.IsNullOrEmpty(s) || s.Length > MaxNameLength) return null;
        return s.Any(char.IsControl) ? null : s;
    }
}
