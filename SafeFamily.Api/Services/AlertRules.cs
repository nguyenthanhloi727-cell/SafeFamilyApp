using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Dtos;

namespace SafeFamily.Api.Services;

/// <summary>
/// Quy tắc cảnh báo cho mẹ (API-10): loại cho phép, kiểm kiểu/độ dài từng trường, chống trùng, giới hạn số dòng và dọn cũ.
/// Detail chỉ là mã/số ngắn: ký tự lạ bị từ chối để không lọt nội dung (tên app, văn bản, vị trí).
/// </summary>
public static partial class AlertRules
{
    public const string TimeChanged = "time_changed";
    public const string AppUninstallAttempt = "app_uninstall_attempt";
    public const string AccessibilityOff = "accessibility_off";
    public const string DeviceAdminOff = "device_admin_off";
    public const string PermissionMissing = "permission_missing";
    /// <summary>Chỉ do server tạo (<see cref="OfflineAlerts"/>): máy mất kết nối thì không tự báo được.</summary>
    public const string Offline = "offline";

    public static readonly string[] Kinds =
        [TimeChanged, AppUninstallAttempt, AccessibilityOff, DeviceAdminOff, PermissionMissing, Offline];

    public const int MaxKindLength = 30;
    public const int MaxDetailLength = 32;
    /// <summary>Số dòng tối đa mỗi máy; vượt thì xóa dòng cũ nhất (không từ chối cảnh báo mới).</summary>
    public const int MaxRowsPerDevice = 200;
    public const int MaxListRows = 100;
    /// <summary>Cùng loại trong cửa sổ này (quanh thời điểm xảy ra) là một sự kiện: không tạo thêm.</summary>
    public static readonly TimeSpan DedupWindow = TimeSpan.FromMinutes(10);
    public static readonly TimeSpan Retention = TimeSpan.FromDays(30);
    /// <summary>Cảnh báo máy con gửi bù không được cũ hơn mức này (hàng chờ trên máy cũng bỏ mục quá hạn).</summary>
    public static readonly TimeSpan MaxEventAge = TimeSpan.FromDays(7);
    static readonly TimeSpan MaxFuture = TimeSpan.FromMinutes(5);

    [GeneratedRegex(@"^-?[a-z0-9_]{1,31}$")]
    private static partial Regex DetailCode();

    public static bool IsKind(string? kind) => kind is not null && Kinds.Contains(kind);

    /// <summary>
    /// Trả về lỗi (tiếng Việt) hoặc null nếu hợp lệ; <paramref name="createdAt"/> = thời điểm xảy ra (UTC) để lưu.
    /// Máy con không được tự gửi <c>offline</c>.
    /// </summary>
    public static string? Validate(PostAlertRequest r, DateTime now, out DateTime createdAt)
    {
        createdAt = now;
        if (!IsKind(r.Kind)) return "Loại cảnh báo không hợp lệ.";
        if (r.Kind == Offline) return "Cảnh báo offline do máy chủ tự tạo.";
        if (r.Detail is { Length: > 0 } d && (d.Length > MaxDetailLength || !DetailCode().IsMatch(d)))
            return "Detail chỉ là mã hoặc số ngắn.";
        if (r.OccurredAt is { } t)
        {
            var utc = t.Kind == DateTimeKind.Unspecified ? DateTime.SpecifyKind(t, DateTimeKind.Utc) : t.ToUniversalTime();
            if (utc > now + MaxFuture) return "Thời điểm ở tương lai.";
            if (utc < now - MaxEventAge) return "Thời điểm quá cũ.";
            createdAt = utc;
        }
        return null;
    }

    public static AlertDto ToDto(Alert a) => new(a.Id, a.Kind, a.Detail, a.CreatedAt, a.ReadAt);

    /// <summary>Dọn cảnh báo quá <see cref="Retention"/> của máy này và chừa chỗ cho một dòng mới (tối đa <see cref="MaxRowsPerDevice"/>).</summary>
    public static async Task TrimAsync(AppDb db, int deviceId, DateTime now, CancellationToken ct = default)
    {
        var cutoff = now - Retention;
        await db.Alerts.Where(a => a.DeviceId == deviceId && a.CreatedAt < cutoff).ExecuteDeleteAsync(ct);
        var count = await db.Alerts.CountAsync(a => a.DeviceId == deviceId, ct);
        if (count < MaxRowsPerDevice) return;
        var oldest = await db.Alerts.Where(a => a.DeviceId == deviceId).OrderBy(a => a.Id)
            .Take(count - MaxRowsPerDevice + 1).Select(a => a.Id).ToListAsync(ct);
        await db.Alerts.Where(a => oldest.Contains(a.Id)).ExecuteDeleteAsync(ct);
    }
}

/// <summary>Tạo cảnh báo "mất kết nối" khi máy con không liên lạc quá ngưỡng (chạy trong <see cref="OfflineAlertService"/>).</summary>
public static class OfflineAlerts
{
    /// <summary>
    /// Mỗi máy chưa hủy ghép có lần liên lạc cuối (hoặc lúc ghép nếu chưa từng) cũ hơn <paramref name="threshold"/> và chưa có
    /// cảnh báo offline nào sau lần liên lạc đó thì tạo MỘT cảnh báo. Máy online lại rồi lại mất mới tạo cảnh báo mới,
    /// nên không tạo trùng liên tục. Trả về số cảnh báo đã tạo. Detail = số giờ mất kết nối (làm tròn xuống).
    /// </summary>
    public static async Task<int> RunOnceAsync(AppDb db, DateTime now, TimeSpan threshold, CancellationToken ct = default)
    {
        var cutoff = now - threshold;
        var due = await db.Devices
            .Where(d => !d.Revoked && (d.LastSeenAt ?? d.PairedAt) < cutoff &&
                !db.Alerts.Any(a => a.DeviceId == d.Id && a.Kind == AlertRules.Offline && a.CreatedAt > (d.LastSeenAt ?? d.PairedAt)))
            .Select(d => new { d.Id, Since = d.LastSeenAt ?? d.PairedAt })
            .ToListAsync(ct);
        foreach (var d in due)
        {
            await AlertRules.TrimAsync(db, d.Id, now, ct);
            var hours = (long)Math.Clamp((now - d.Since).TotalHours, 0, 999_999_999);
            db.Alerts.Add(new Alert { DeviceId = d.Id, Kind = AlertRules.Offline, Detail = hours.ToString(), CreatedAt = now });
        }
        if (due.Count > 0) await db.SaveChangesAsync(ct);
        return due.Count;
    }
}

/// <summary>
/// Tác vụ nền (API-10): định kỳ tìm máy con mất kết nối. Cấu hình: <c>Alerts:OfflineHours</c> (mặc định 24) và
/// <c>Alerts:CheckIntervalSeconds</c> (mặc định 900). Lỗi (ví dụ CSDL chưa sẵn sàng) chỉ ghi log, lượt sau thử lại.
/// </summary>
public class OfflineAlertService(IServiceScopeFactory scopes, IConfiguration config, ILogger<OfflineAlertService> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var hours = config.GetValue("Alerts:OfflineHours", 24.0);
        var seconds = config.GetValue("Alerts:CheckIntervalSeconds", 900);
        if (hours <= 0 || seconds < 1)
        {
            log.LogWarning("Alerts:OfflineHours / CheckIntervalSeconds không hợp lệ, không chạy kiểm tra mất kết nối.");
            return;
        }
        var threshold = TimeSpan.FromHours(hours);
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(seconds));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDb>();
                await OfflineAlerts.RunOnceAsync(db, DateTime.UtcNow, threshold, stoppingToken);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log.LogWarning(e, "Kiểm tra máy con mất kết nối lỗi, thử lại lượt sau.");
            }
        }
    }
}
