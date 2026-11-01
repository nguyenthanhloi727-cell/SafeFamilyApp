using Microsoft.AspNetCore.Http.Features;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;

namespace SafeFamily.Api.Services;

/// <summary>Hằng số nền tảng (API-14): phiên bản API và giới hạn body.</summary>
public static class PlatformRules
{
    /// <summary>Phiên bản hợp đồng API. Chỉ tăng khi có thay đổi phá vỡ; thêm trường/endpoint mới thì giữ nguyên.</summary>
    public const string ApiVersion = "1";

    /// <summary>Tiền tố phiên bản: <c>/api/v1/x</c> là bí danh của <c>/api/x</c> (giữ cả đường dẫn cũ cho app đã phát hành).</summary>
    public const string VersionPrefix = "/api/v1/";

    /// <summary>Trần body mặc định (byte). Lớn nhất hiện nay: danh sách ≤2000 app (~vài trăm KB). Cấu hình <c>Limits:MaxBodyBytes</c>.</summary>
    public const long DefaultMaxBodyBytes = 2 * 1024 * 1024;

    public static string? RewriteVersionedPath(string path) =>
        path.StartsWith(VersionPrefix, StringComparison.OrdinalIgnoreCase) ? "/api/" + path[VersionPrefix.Length..] : null;
}

/// <summary>
/// Middleware nền tảng (API-14): đổi <c>/api/v1/...</c> thành <c>/api/...</c> trước khi định tuyến, gắn header
/// <c>X-Api-Version</c> vào mọi phản hồi, và chặn body quá lớn (413) kể cả khi không có Content-Length.
/// Header <c>X-App-Version</c> của app (nếu có) chỉ được ghi vào log, không dùng để từ chối: bản app cũ vẫn chạy.
/// </summary>
public class PlatformMiddleware(RequestDelegate next, long maxBodyBytes)
{
    public async Task InvokeAsync(HttpContext ctx)
    {
        var rewritten = PlatformRules.RewriteVersionedPath(ctx.Request.Path.Value ?? "");
        if (rewritten is not null) ctx.Request.Path = rewritten;
        ctx.Response.Headers["X-Api-Version"] = PlatformRules.ApiVersion;

        if (ctx.Request.ContentLength is long len && len > maxBodyBytes)
        {
            await Results.Problem(
                statusCode: StatusCodes.Status413PayloadTooLarge,
                title: "Dữ liệu gửi lên quá lớn.",
                extensions: new Dictionary<string, object?> { ["error"] = "Dữ liệu gửi lên quá lớn." }).ExecuteAsync(ctx);
            return;
        }
        var feature = ctx.Features.Get<IHttpMaxRequestBodySizeFeature>();
        if (feature is { IsReadOnly: false }) feature.MaxRequestBodySize = maxBodyBytes;
        await next(ctx);
    }
}

/// <summary>Dọn dữ liệu cũ theo thời hạn giữ của từng loại (API-14). Mỗi loại là một câu <c>ExecuteDelete</c> độc lập.</summary>
public static class DataCleanup
{
    /// <summary>Lịch sử lệnh hiển thị cho mẹ (50 lệnh gần nhất); lệnh cũ hơn mức này không còn ý nghĩa.</summary>
    public static readonly TimeSpan CommandRetention = TimeSpan.FromDays(30);
    /// <summary>Mã ghép / token / mã đặt lại mật khẩu: chỉ xóa sau khi hết hạn hoặc đã dùng quá khoảng này.</summary>
    public static readonly TimeSpan ExpiredGrace = TimeSpan.FromDays(1);

    /// <summary>Trả về tổng số dòng đã xóa.</summary>
    public static async Task<int> RunOnceAsync(AppDb db, DateTime now, CancellationToken ct = default)
    {
        var graceCutoff = now - ExpiredGrace;
        var oldestDay = DateOnly.FromDateTime(now).AddDays(-UsageRules.RetentionDays);
        var n = 0;
        n += await db.LocationPoints.Where(l => l.Time < now - LocationRules.Retention).ExecuteDeleteAsync(ct);
        n += await db.UsageDays.Where(u => u.Date < oldestDay).ExecuteDeleteAsync(ct); // UsageApps xóa theo (cascade)
        n += await db.ChildRequests.Where(r => r.CreatedAt < now - RequestRules.DecidedRetention).ExecuteDeleteAsync(ct);
        n += await db.Alerts.Where(a => a.CreatedAt < now - AlertRules.Retention).ExecuteDeleteAsync(ct);
        n += await db.Commands.Where(c => c.CreatedAt < now - CommandRetention).ExecuteDeleteAsync(ct);
        n += await db.Pairings.Where(p => p.ExpiresAt < graceCutoff || (p.UsedAt != null && p.UsedAt < graceCutoff)).ExecuteDeleteAsync(ct);
        n += await db.RefreshTokens.Where(t => t.ExpiresAt < graceCutoff || (t.RevokedAt != null && t.RevokedAt < graceCutoff)).ExecuteDeleteAsync(ct);
        n += await db.PasswordResets.Where(r => r.ExpiresAt < graceCutoff || (r.UsedAt != null && r.UsedAt < graceCutoff)).ExecuteDeleteAsync(ct);
        return n;
    }
}

/// <summary>
/// Tác vụ nền (API-14): định kỳ gọi <see cref="DataCleanup"/>. Cấu hình <c>Cleanup:IntervalSeconds</c> (mặc định 21600 = 6 giờ;
/// 0 hoặc âm = tắt). Lỗi chỉ ghi log, lượt sau thử lại.
/// </summary>
public class DataCleanupService(IServiceScopeFactory scopes, IConfiguration config, ILogger<DataCleanupService> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var seconds = config.GetValue("Cleanup:IntervalSeconds", 21600);
        if (seconds < 1)
        {
            log.LogInformation("Cleanup:IntervalSeconds <= 0, không chạy dọn dữ liệu định kỳ.");
            return;
        }
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(seconds));
        do
        {
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDb>();
                var removed = await DataCleanup.RunOnceAsync(db, DateTime.UtcNow, stoppingToken);
                if (removed > 0) log.LogInformation("Dọn dữ liệu cũ: xóa {Rows} dòng.", removed);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log.LogWarning(e, "Dọn dữ liệu cũ lỗi, thử lại lượt sau.");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}
