using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Services;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>API-14: /health, bí danh /api/v1, ProblemDetails, trần body, trần tần suất máy con, băm mật khẩu, JWT, CORS, dọn dữ liệu.</summary>
public class PlatformTests(SharedApi shared) : TestBase(shared)
{
    static async Task<JsonElement> Problem(HttpResponseMessage r)
    {
        Assert.Equal("application/problem+json", r.Content.Headers.ContentType?.MediaType);
        return await Api.Json(r);
    }

    // ---- /health, phiên bản ----

    [Fact]
    public async Task Health_IsAnonymous_AndReportsOk()
    {
        var r = await Api.Get("/health");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var j = await Api.Json(r);
        Assert.Equal("ok", j.GetProperty("status").GetString());
        Assert.Equal("1", j.GetProperty("apiVersion").GetString());
        Assert.Equal("1", r.Headers.GetValues("X-Api-Version").Single());
    }

    [Fact]
    public async Task V1Prefix_IsAnAliasOfApi_AndOldPathsKeepWorking()
    {
        var email = Api.UniqueEmail();
        var reg = await Api.Post("/api/v1/auth/register", null, new { email, password = "password123" });
        Assert.Equal(HttpStatusCode.OK, reg.StatusCode);
        var token = (await Api.Json(reg)).GetProperty("accessToken").GetString()!;
        await Expect(HttpStatusCode.OK, Api.Get("/api/v1/devices", token));
        await Expect(HttpStatusCode.OK, Api.Get("/api/devices", token));
        await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/v1/devices"));
        await Expect(HttpStatusCode.NotFound, Api.Get("/api/v1/khong-co", token));
    }

    [Fact]
    public async Task AppVersionHeader_IsIgnored_SoOldAndNewAppsBothWork()
    {
        foreach (var version in new[] { "0.0.1", "99.0.0", "rac<>", "" })
        {
            var req = new HttpRequestMessage(HttpMethod.Get, "/health");
            req.Headers.TryAddWithoutValidation("X-App-Version", version);
            var r = await Factory.CreateClient().SendAsync(req);
            Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        }
    }

    // ---- ProblemDetails thống nhất ----

    [Fact]
    public async Task Errors_AreProblemDetails_WithErrorFieldForTheApp()
    {
        var notFound = await Api.Get("/api/khong-co");
        Assert.Equal(HttpStatusCode.NotFound, notFound.StatusCode);
        var j = await Problem(notFound);
        Assert.Equal(404, j.GetProperty("status").GetInt32());
        Assert.False(string.IsNullOrWhiteSpace(j.GetProperty("error").GetString()));
        Assert.False(string.IsNullOrWhiteSpace(j.GetProperty("traceId").GetString()));

        var unauthorized = await Api.Get("/api/devices");
        Assert.Equal(HttpStatusCode.Unauthorized, unauthorized.StatusCode);
        Assert.Equal(401, (await Problem(unauthorized)).GetProperty("status").GetInt32());

        var bad = await Api.Post("/api/auth/login", null, "{}");
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);
        Assert.False(string.IsNullOrWhiteSpace((await Problem(bad)).GetProperty("error").GetString()));
    }

    // ---- Trần body ----

    [Fact]
    public async Task OversizedBody_Is413_Problem()
    {
        var body = "{\"email\":\"" + new string('a', 2 * 1024 * 1024 + 10) + "\"}";
        var r = await Api.Post("/api/auth/login", null, body);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, r.StatusCode);
        Assert.Equal(413, (await Problem(r)).GetProperty("status").GetInt32());
    }

    [Fact]
    public async Task BodyUnderTheCap_IsHandledByTheEndpointRules_Not413()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        // Policy 100 KiB vượt trần riêng 64 KiB của API-04 (400) nhưng dưới trần chung (không phải 413).
        var r = await mom.Put(kid.Url("/policy"), new { json = "{\"x\":\"" + new string('a', 100 * 1024) + "\"}", expectedVersion = 0 });
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
    }

    // ---- Trần tần suất máy con ----

    [Fact]
    public async Task DeviceEndpoints_AreRateLimitedPerDevice()
    {
        using var limited = new ApiFactory(devicePerMinute: 3);
        var api = new Api(limited);
        var mom = await api.NewMother();
        var kid1 = await mom.PairKid("A");
        var kid2 = await mom.PairKid("B");
        for (var i = 0; i < 3; i++)
            await Expect(HttpStatusCode.OK, kid1.Get("/api/devices/me/policy"), $"lần {i + 1}");
        var over = await kid1.Get("/api/devices/me/policy");
        Assert.Equal(HttpStatusCode.TooManyRequests, over.StatusCode);
        Assert.Equal(429, (await Problem(over)).GetProperty("status").GetInt32());
        Assert.True(over.Headers.Contains("Retry-After"));
        // Máy khác của cùng nhà và phía mẹ không bị tính chung.
        await Expect(HttpStatusCode.OK, kid2.Get("/api/devices/me/policy"));
        await Expect(HttpStatusCode.OK, mom.Get("/api/devices"));
    }

    // ---- Băm mật khẩu ----

    [Fact]
    public void PasswordHasher_UsesCurrentIterations_AndStillVerifiesLegacyHashes()
    {
        var hash = PasswordHasher.Hash("matkhau-moi-123");
        Assert.StartsWith("600000.", hash);
        Assert.True(PasswordHasher.Verify("matkhau-moi-123", hash));
        Assert.False(PasswordHasher.Verify("sai", hash));
        Assert.False(PasswordHasher.NeedsRehash(hash));

        var legacy = LegacyHash("matkhau-cu-123", 120_000);
        Assert.True(PasswordHasher.Verify("matkhau-cu-123", legacy));
        Assert.True(PasswordHasher.NeedsRehash(legacy));

        foreach (var junk in new[] { "", "x", "1.2", "a.b.c", "100.@@@.@@@", "0.AAAA.AAAA", "-5.AAAA.AAAA" })
            Assert.False(PasswordHasher.Verify("x", junk), junk);
    }

    [Fact]
    public async Task Login_WithLegacyHash_Succeeds_AndUpgradesTheHash()
    {
        var mom = await Api.NewMother();
        await Factory.WithDb(async db =>
        {
            var p = await db.Parents.SingleAsync(x => x.Email == mom.Email);
            p.PasswordHash = LegacyHash("password123", 120_000);
            await db.SaveChangesAsync();
        });
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/auth/login", null, new { email = mom.Email, password = "sai-mat-khau" }));
        await Expect(HttpStatusCode.OK, Api.Post("/api/auth/login", null, new { email = mom.Email, password = "password123" }));
        await Factory.WithDb(async db =>
        {
            var p = await db.Parents.SingleAsync(x => x.Email == mom.Email);
            Assert.StartsWith("600000.", p.PasswordHash);
        });
        await Expect(HttpStatusCode.OK, Api.Post("/api/auth/login", null, new { email = mom.Email, password = "password123" }));
    }

    static string LegacyHash(string password, int iterations)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var h = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, 32);
        return $"{iterations}.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(h)}";
    }

    // ---- JWT ----

    [Fact]
    public async Task Jwt_RejectsUnsignedTokens_AndExpiredBeyondSkew()
    {
        var mom = await Api.NewMother();
        // Token không chữ ký (alg=none) tự dựng, đúng claim, còn hạn: phải bị từ chối.
        static string B64(string json) => Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(json)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var exp = DateTimeOffset.UtcNow.AddMinutes(10).ToUnixTimeSeconds();
        var none = B64("{\"alg\":\"none\",\"typ\":\"JWT\"}") + "." +
            B64($"{{\"sub\":\"1\",\"fam\":\"{mom.FamilyId}\",\"http://schemas.microsoft.com/ws/2008/06/identity/claims/role\":\"parent\",\"iss\":\"SafeFamily.Api\",\"aud\":\"SafeFamily.App\",\"exp\":{exp}}}") + ".";
        await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/devices", none), "alg=none");
        var expired = Tokens.Make("parent", 1, mom.FamilyId, TimeSpan.FromMinutes(-2));
        await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/devices", expired), "hết hạn 2 phút trước");
        var valid = Tokens.Make("parent", 1, mom.FamilyId, TimeSpan.FromMinutes(5));
        await Expect(HttpStatusCode.OK, Api.Get("/api/devices", valid), "còn hạn, ký đúng HS256");
    }

    // ---- CORS chặt ----

    [Fact]
    public async Task Cors_ByDefault_AddsNoAllowOriginHeader()
    {
        var req = new HttpRequestMessage(HttpMethod.Options, "/api/devices");
        req.Headers.TryAddWithoutValidation("Origin", "https://trang-la.example");
        req.Headers.TryAddWithoutValidation("Access-Control-Request-Method", "GET");
        var r = await Factory.CreateClient().SendAsync(req);
        Assert.False(r.Headers.Contains("Access-Control-Allow-Origin"));
    }

    // ---- Dọn dữ liệu ----

    [Fact]
    public async Task DataCleanup_RemovesOnlyExpiredRows()
    {
        using var f = new ApiFactory();
        var api = new Api(f);
        var mom = await api.NewMother();
        var kid = await mom.PairKid();
        var now = DateTime.UtcNow;
        int removed = 0;
        await f.WithDb(async db =>
        {
            // Mỗi loại: một dòng cũ (phải bị xóa) và một dòng mới (phải còn).
            db.LocationPoints.AddRange(
                new LocationPoint { DeviceId = kid.Id, Time = now.AddDays(-8) },
                new LocationPoint { DeviceId = kid.Id, Time = now.AddDays(-1) });
            db.Alerts.AddRange(
                new Alert { DeviceId = kid.Id, Kind = "time_changed", CreatedAt = now.AddDays(-31) },
                new Alert { DeviceId = kid.Id, Kind = "time_changed", CreatedAt = now.AddDays(-2) });
            db.Commands.AddRange(
                new Command { DeviceId = kid.Id, Type = "x", CreatedAt = now.AddDays(-31) },
                new Command { DeviceId = kid.Id, Type = "x", CreatedAt = now.AddDays(-3) });
            db.ChildRequests.AddRange(
                new ChildRequest { DeviceId = kid.Id, Kind = "study_done", CreatedAt = now.AddDays(-8) },
                new ChildRequest { DeviceId = kid.Id, Kind = "study_done", CreatedAt = now.AddDays(-1) });
            var today = DateOnly.FromDateTime(now);
            db.UsageDays.AddRange(
                new UsageDay { DeviceId = kid.Id, Date = today.AddDays(-91), Apps = [new UsageApp { Package = "a.b", Minutes = 1 }] },
                new UsageDay { DeviceId = kid.Id, Date = today.AddDays(-5), Apps = [new UsageApp { Package = "a.b", Minutes = 1 }] });
            db.Pairings.AddRange(
                new Pairing { FamilyId = mom.FamilyId, Code = "111111", ExpiresAt = now.AddDays(-2) },
                new Pairing { FamilyId = mom.FamilyId, Code = "222222", ExpiresAt = now.AddMinutes(5), UsedAt = now.AddDays(-2) },
                new Pairing { FamilyId = mom.FamilyId, Code = "333333", ExpiresAt = now.AddMinutes(5) },
                new Pairing { FamilyId = mom.FamilyId, Code = "444444", ExpiresAt = now.AddMinutes(-5) }); // mới hết hạn: còn trong thời gian ân hạn
            var parent = await db.Parents.SingleAsync(p => p.Email == mom.Email);
            db.RefreshTokens.AddRange(
                new RefreshToken { ParentId = parent.Id, TokenHash = "old-expired", ExpiresAt = now.AddDays(-2) },
                new RefreshToken { ParentId = parent.Id, TokenHash = "old-revoked", ExpiresAt = now.AddDays(10), RevokedAt = now.AddDays(-2) },
                new RefreshToken { ParentId = parent.Id, TokenHash = "alive", ExpiresAt = now.AddDays(10) });
            db.PasswordResets.AddRange(
                new PasswordReset { ParentId = parent.Id, CodeHash = "old", ExpiresAt = now.AddDays(-2) },
                new PasswordReset { ParentId = parent.Id, CodeHash = "fresh", ExpiresAt = now.AddMinutes(20) });
            await db.SaveChangesAsync();
            removed = await DataCleanup.RunOnceAsync(db, now);
        });
        // (mã ghép của PairKid, đã dùng gần đây, còn trong ân hạn nên không bị xóa)
        // 1 vị trí + 1 cảnh báo + 1 lệnh + 1 yêu cầu + 1 ngày báo cáo + 2 mã ghép + 2 refresh token + 1 mã đặt lại = 10
        // (dòng UsageApps của ngày bị xóa đi theo cascade, không tính vào số này).
        Assert.Equal(10, removed);
        await f.WithDb(async db =>
        {
            Assert.Equal(1, await db.LocationPoints.CountAsync());
            Assert.Equal(1, await db.Alerts.CountAsync());
            Assert.Equal(1, await db.Commands.CountAsync(c => c.Type == "x"));
            Assert.Equal(1, await db.ChildRequests.CountAsync());
            Assert.Equal(1, await db.UsageDays.CountAsync());
            Assert.Equal(1, await db.UsageApps.CountAsync());
            Assert.Equal(new[] { "333333", "444444" }, await db.Pairings.Where(p => p.Code == "111111" || p.Code == "222222" || p.Code == "333333" || p.Code == "444444").OrderBy(p => p.Code).Select(p => p.Code).ToArrayAsync());
            Assert.Equal(new[] { "alive" }, await db.RefreshTokens.Where(t => t.TokenHash == "alive" || t.TokenHash.StartsWith("old")).Select(t => t.TokenHash).ToArrayAsync());
            Assert.Equal(new[] { "fresh" }, await db.PasswordResets.Select(r => r.CodeHash).ToArrayAsync());
            Assert.Equal(0, await DataCleanup.RunOnceAsync(db, now)); // lần hai không còn gì để xóa
        });
        await Expect(HttpStatusCode.OK, kid.Get("/api/devices/me/policy")); // máy con vẫn dùng bình thường
    }
}
