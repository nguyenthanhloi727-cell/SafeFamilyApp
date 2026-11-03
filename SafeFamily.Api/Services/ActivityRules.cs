using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Dtos;

namespace SafeFamily.Api.Services;

/// <summary>
/// Nhật ký hoạt động của máy con (T8): con mở app bị chặn, nhập sai PIN / cố vào khu phụ huynh, phụ huynh mở khóa.
/// Chỉ có loại sự kiện, tên gói (với <c>blocked_app_open</c>) và thời điểm: không nội dung, không vị trí.
/// </summary>
public static partial class ActivityRules
{
    public const string BlockedAppOpen = "blocked_app_open";
    public const string ParentAuthFailed = "parent_auth_failed";
    public const string ParentUnlocked = "parent_unlocked";

    public static readonly string[] Kinds = [BlockedAppOpen, ParentAuthFailed, ParentUnlocked];

    public const int MaxKindLength = 30;
    public const int MaxDetailLength = 100;
    /// <summary>Số sự kiện tối đa trong một lô gửi lên.</summary>
    public const int MaxBatch = 50;
    /// <summary>Số dòng tối đa mỗi máy; vượt thì xóa dòng cũ nhất (không từ chối sự kiện mới).</summary>
    public const int MaxRowsPerDevice = 1000;
    public const int MaxListRows = 100;
    public static readonly TimeSpan Retention = TimeSpan.FromDays(30);
    static readonly TimeSpan MaxFuture = TimeSpan.FromMinutes(5);

    [GeneratedRegex(@"^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$")]
    private static partial Regex PackageName();

    public static bool IsKind(string? kind) => kind is not null && Kinds.Contains(kind);

    /// <summary>
    /// Trả về lỗi (tiếng Việt) hoặc null nếu hợp lệ. <c>blocked_app_open</c> bắt buộc có <c>detail</c> là tên gói;
    /// hai loại còn lại không có <c>detail</c>. Sự kiện quá <see cref="Retention"/> hoặc ở tương lai quá 5 phút bị từ chối.
    /// </summary>
    public static string? Validate(PostActivityRequest r, DateTime now)
    {
        if (r.Events.Count == 0) return "Không có sự kiện nào.";
        if (r.Events.Count > MaxBatch) return "Quá nhiều sự kiện.";
        foreach (var e in r.Events)
        {
            if (!IsKind(e.Kind)) return "Loại hoạt động không hợp lệ.";
            if (e.Kind == BlockedAppOpen)
            {
                if (string.IsNullOrEmpty(e.Detail) || e.Detail.Length > MaxDetailLength || !PackageName().IsMatch(e.Detail))
                    return "Detail phải là tên gói app.";
            }
            else if (!string.IsNullOrEmpty(e.Detail)) return "Loại này không có detail.";
            var utc = ToUtc(e.OccurredAt);
            if (utc > now + MaxFuture) return "Thời điểm ở tương lai.";
            if (utc < now - Retention) return "Thời điểm quá cũ.";
        }
        return null;
    }

    public static DateTime ToUtc(DateTime t) =>
        t.Kind == DateTimeKind.Unspecified ? DateTime.SpecifyKind(t, DateTimeKind.Utc) : t.ToUniversalTime();

    public static ActivityDto ToDto(ActivityEvent a) => new(a.Id, a.Kind, a.Detail, a.Time);

    /// <summary>Dọn dòng quá <see cref="Retention"/> và chừa chỗ cho <paramref name="incoming"/> dòng mới (tối đa <see cref="MaxRowsPerDevice"/>).</summary>
    public static async Task TrimAsync(AppDb db, int deviceId, DateTime now, int incoming, CancellationToken ct = default)
    {
        var cutoff = now - Retention;
        await db.ActivityEvents.Where(a => a.DeviceId == deviceId && a.Time < cutoff).ExecuteDeleteAsync(ct);
        var excess = await db.ActivityEvents.CountAsync(a => a.DeviceId == deviceId, ct) + incoming - MaxRowsPerDevice;
        if (excess <= 0) return;
        var oldest = await db.ActivityEvents.Where(a => a.DeviceId == deviceId).OrderBy(a => a.Id)
            .Take(excess).Select(a => a.Id).ToListAsync(ct);
        await db.ActivityEvents.Where(a => oldest.Contains(a.Id)).ExecuteDeleteAsync(ct);
    }
}
