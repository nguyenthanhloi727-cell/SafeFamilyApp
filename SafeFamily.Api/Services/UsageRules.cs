using System.Globalization;
using SafeFamily.Api.Dtos;

namespace SafeFamily.Api.Services;

/// <summary>
/// Quy tắc báo cáo sử dụng (API-08). Server chỉ nhận phút theo app theo ngày: kiểm kiểu, số lượng và độ dài
/// từng trường, không nhận thêm gì khác (không nội dung, không vị trí).
/// </summary>
public static class UsageRules
{
    /// <summary>Số ngày tối đa một lô: máy con giữ 30 ngày + hôm nay.</summary>
    public const int MaxDaysPerBatch = 31;
    public const int MaxAppsPerDay = 200;
    public const int MaxMinutes = 24 * 60;
    public const int MaxBlocks = 10_000;
    /// <summary>Giữ bao nhiêu ngày (đề xuất ở API_DAY_DU mục 5, câu 2).</summary>
    public const int RetentionDays = 90;
    /// <summary>Ngày ở tương lai tối đa so với ngày UTC hiện tại: dư 1 ngày cho múi giờ lệch tới +14.</summary>
    public const int MaxFutureDays = 1;
    /// <summary>Khoảng from..to tối đa mẹ được hỏi một lần.</summary>
    public const int MaxRangeDays = RetentionDays;

    public const string DateFormat = "yyyy-MM-dd";

    public static bool TryParseDate(string? s, out DateOnly date) =>
        DateOnly.TryParseExact(s, DateFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out date);

    public static string Format(DateOnly d) => d.ToString(DateFormat, CultureInfo.InvariantCulture);

    /// <summary>Trả về lỗi (tiếng Việt) hoặc null. <paramref name="today"/> là ngày UTC hiện tại (để test cố định).</summary>
    public static string? Validate(PostUsageRequest r, DateOnly today)
    {
        if (r.Days is null || r.Days.Count == 0) return "Thiếu dữ liệu.";
        if (r.Days.Count > MaxDaysPerBatch) return "Quá nhiều ngày.";
        var seen = new HashSet<DateOnly>();
        var oldest = today.AddDays(-RetentionDays);
        var newest = today.AddDays(MaxFutureDays);
        foreach (var d in r.Days)
        {
            if (d is null) return "Ngày không hợp lệ.";
            if (!TryParseDate(d.Date, out var date)) return "Ngày không hợp lệ.";
            if (date > newest) return "Ngày ở tương lai.";
            if (date < oldest) return "Ngày quá cũ.";
            if (!seen.Add(date)) return "Trùng ngày trong lô.";
            if (d.TotalMinutes is < 0 or > MaxMinutes) return "Số phút không hợp lệ.";
            if (d.Blocks is < 0 or > MaxBlocks) return "Số lần chặn không hợp lệ.";
            if (d.Apps is null) return "Thiếu danh sách app.";
            if (d.Apps.Count > MaxAppsPerDay) return "Quá nhiều app trong một ngày.";
            foreach (var (pkg, minutes) in d.Apps)
            {
                if (!CommandRules.IsPackage(pkg)) return "Tên gói không hợp lệ.";
                if (minutes is < 0 or > MaxMinutes) return "Số phút không hợp lệ.";
            }
        }
        return null;
    }
}
