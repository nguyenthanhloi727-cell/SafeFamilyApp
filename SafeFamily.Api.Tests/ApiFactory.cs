using Xunit;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using SafeFamily.Api.Data;

namespace SafeFamily.Api.Tests;

/// <summary>
/// Chạy API thật trong bộ nhớ trên một CSDL LocalDB tạm (tên ngẫu nhiên, tạo bằng Migrate để kiểm luôn migration)
/// và xóa khi xong. Không đụng CSDL dev. Cần LocalDB: <c>sqllocaldb i</c> phải thấy MSSQLLocalDB.
/// </summary>
public sealed class ApiFactory(int claimPer10Min = 100_000) : WebApplicationFactory<Program>
{
    public const string JwtKey = "api-tests-jwt-key-api-tests-jwt-key-0123456789";
    readonly string _db = "SafeFamilyTest_" + Guid.NewGuid().ToString("N");

    string ConnectionString =>
        $@"Server=(localdb)\MSSQLLocalDB;Database={_db};Integrated Security=true;TrustServerCertificate=true;Encrypt=false";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:Default", ConnectionString);
        builder.UseSetting("Jwt:Key", JwtKey);
        builder.UseSetting("RateLimit:AuthPerMinute", "100000");
        builder.UseSetting("RateLimit:ClaimPer10Min", claimPer10Min.ToString());
        builder.UseSetting("Alerts:OfflineHours", "0"); // tắt tác vụ nền kiểm máy offline: test tự gọi OfflineAlerts nếu cần
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        var host = base.CreateHost(builder);
        using var scope = host.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<AppDb>().Database.Migrate();
        return host;
    }

    /// <summary>Đọc/sửa trực tiếp CSDL tạm (ví dụ ép mã ghép hết hạn).</summary>
    public async Task WithDb(Func<AppDb, Task> action)
    {
        using var scope = Services.CreateScope();
        await action(scope.ServiceProvider.GetRequiredService<AppDb>());
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            try
            {
                using var scope = Services.CreateScope();
                scope.ServiceProvider.GetRequiredService<AppDb>().Database.EnsureDeleted();
            }
            catch { /* LocalDB đã tắt: không còn gì để xóa */ }
            SqlConnection.ClearAllPools();
        }
        base.Dispose(disposing);
    }
}

/// <summary>Một factory dùng chung cho mọi lớp test (tạo CSDL một lần).</summary>
public class SharedApi : IDisposable
{
    public ApiFactory Factory { get; } = new();
    public void Dispose() => Factory.Dispose();
}

[CollectionDefinition("api")]
public class ApiCollection : ICollectionFixture<SharedApi>;
