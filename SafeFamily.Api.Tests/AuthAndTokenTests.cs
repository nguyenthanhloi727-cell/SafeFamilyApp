using System.Net;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>Ghép đôi (mã dùng lại), token bị thu hồi (hủy ghép, refresh đã đổi), token giả/hết hạn, sai vai trò.</summary>
public class AuthAndTokenTests(SharedApi shared) : TestBase(shared)
{
    // ---- Mã ghép ----

    [Fact]
    public async Task PairingCode_Reused_Is400()
    {
        var mom = await Api.NewMother();
        var code = await mom.NewCode();
        await Expect(HttpStatusCode.OK, Api.Post("/api/pairing/claim", null, new { code }), "lần nhập đầu");
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/pairing/claim", null, new { code }), "lần nhập thứ hai");
    }

    [Fact]
    public async Task PairingCode_Expired_Is400()
    {
        var mom = await Api.NewMother();
        var code = await mom.NewCode();
        await Factory.WithDb(async db =>
        {
            var p = db.Pairings.Single(x => x.Code == code && x.UsedAt == null);
            p.ExpiresAt = DateTime.UtcNow.AddMinutes(-1);
            await db.SaveChangesAsync();
        });
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/pairing/claim", null, new { code }));
    }

    [Theory]
    [InlineData("""{"code":"12345"}""")]       // thiếu 1 số
    [InlineData("""{"code":"1234567"}""")]     // thừa 1 số
    [InlineData("""{"code":""}""")]
    [InlineData("""{"code":null}""")]
    [InlineData("""{"code":123456}""")]        // sai kiểu
    [InlineData("""{}""")]
    [InlineData("""{"code":"abcdef"}""")]      // đúng độ dài, không có mã nào như vậy
    public async Task PairingCode_BadShape_Is400(string body) =>
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/pairing/claim", null, body));

    [Fact]
    public async Task PairingCode_NewCode_DoesNotInvalidateOtherFamilyCode()
    {
        var a = await Api.NewMother();
        var b = await Api.NewMother();
        var codeA = await a.NewCode("Con A");
        await b.NewCode("Con B"); // mẹ B tạo mã mới không được làm mất mã còn hạn của mẹ A
        var kid = await Api.Post("/api/pairing/claim", null, new { code = codeA });
        Assert.Equal(HttpStatusCode.OK, kid.StatusCode);
        Assert.Equal("Con A", (await Api.Json(kid)).GetProperty("deviceName").GetString());
    }

    [Fact]
    public async Task PairingCode_DeviceNameTooLong_Is400_AndOnlyParentMayCreate()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Expect(HttpStatusCode.BadRequest, mom.Post("/api/pairing/code", new { deviceName = Pad(101) }));
        await Expect(HttpStatusCode.OK, mom.Post("/api/pairing/code", new { deviceName = Pad(100) }));
        await Expect(HttpStatusCode.Forbidden, kid.Post("/api/pairing/code", new { deviceName = "x" }));
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/pairing/code", null, new { deviceName = "x" }));
    }

    [Fact]
    public async Task PairingClaim_IsRateLimited_AfterTooManyTries()
    {
        using var limited = new ApiFactory(claimPer10Min: 3);
        var api = new Api(limited);
        for (var i = 0; i < 3; i++)
            await Expect(HttpStatusCode.BadRequest, api.Post("/api/pairing/claim", null, new { code = "000000" }), $"lần {i + 1}");
        await Expect(HttpStatusCode.TooManyRequests, api.Post("/api/pairing/claim", null, new { code = "000000" }), "lần vượt trần");
    }

    // ---- Đăng ký / đăng nhập ----

    [Fact]
    public async Task Register_Duplicate_Is409_AndBadInput_Is400()
    {
        var mom = await Api.NewMother();
        await Expect(HttpStatusCode.Conflict, Api.Post("/api/auth/register", null, new { email = mom.Email.ToUpperInvariant(), password = "password123" }));
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/auth/register", null, new { email = "khong-phai-email", password = "password123" }));
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/auth/register", null, new { email = Api.UniqueEmail(), password = "short" }));
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/auth/register", null, new { email = Api.UniqueEmail(), password = Pad(129) }));
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/auth/register", null, new { email = Api.UniqueEmail(), password = "password123", familyName = Pad(101) }));
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/auth/register", null, new { password = "password123" }));
    }

    [Fact]
    public async Task Login_WrongPasswordAndUnknownEmail_SameAnswer()
    {
        var mom = await Api.NewMother();
        var wrong = await Api.Post("/api/auth/login", null, new { email = mom.Email, password = "sai-mat-khau" });
        var unknown = await Api.Post("/api/auth/login", null, new { email = Api.UniqueEmail(), password = "password123" });
        Assert.Equal(HttpStatusCode.Unauthorized, wrong.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, unknown.StatusCode);
        Assert.Equal(await wrong.Content.ReadAsStringAsync(), await unknown.Content.ReadAsStringAsync());
        await Expect(HttpStatusCode.OK, Api.Post("/api/auth/login", null, new { email = mom.Email, password = "password123" }));
    }

    // ---- Refresh token ----

    [Fact]
    public async Task Refresh_RotatedToken_Is401_NewTokenWorks()
    {
        var mom = await Api.NewMother();
        var first = await Api.Post("/api/auth/refresh", null, new { refreshToken = mom.Refresh });
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        var fresh = (await Api.Json(first)).GetProperty("refreshToken").GetString();
        Assert.NotEqual(mom.Refresh, fresh);

        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/auth/refresh", null, new { refreshToken = mom.Refresh }), "token cũ đã đổi");
        await Expect(HttpStatusCode.OK, Api.Post("/api/auth/refresh", null, new { refreshToken = fresh }), "token mới");
    }

    [Theory]
    [InlineData("""{"refreshToken":"khong-co-token-nay"}""", HttpStatusCode.Unauthorized)]
    [InlineData("""{"refreshToken":""}""", HttpStatusCode.BadRequest)]
    [InlineData("""{}""", HttpStatusCode.BadRequest)]
    [InlineData("""{"refreshToken":123}""", HttpStatusCode.BadRequest)]
    public async Task Refresh_BadToken(string body, HttpStatusCode expected) =>
        await Expect(expected, Api.Post("/api/auth/refresh", null, body));

    [Fact]
    public async Task Refresh_Expired_Is401()
    {
        var mom = await Api.NewMother();
        await Factory.WithDb(async db =>
        {
            var hash = SafeFamily.Api.Services.TokenService.Hash(mom.Refresh);
            db.RefreshTokens.Single(t => t.TokenHash == hash).ExpiresAt = DateTime.UtcNow.AddMinutes(-1);
            await db.SaveChangesAsync();
        });
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/auth/refresh", null, new { refreshToken = mom.Refresh }));
    }

    // ---- Hủy ghép: token máy con hết tác dụng ----

    [Fact]
    public async Task UnpairedDevice_Token_Is401_OnEveryDeviceEndpoint()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Expect(HttpStatusCode.OK, kid.Get("/api/devices/me"), "trước khi hủy");
        await Expect(HttpStatusCode.NoContent, mom.Delete(kid.Url()));

        var now = DateTime.UtcNow.ToString("O");
        var calls = new (HttpMethod, string, object?)[]
        {
            (HttpMethod.Get, "/api/devices/me", null),
            (HttpMethod.Get, "/api/devices/me/settings", null),
            (HttpMethod.Get, "/api/devices/me/policy", null),
            (HttpMethod.Get, "/api/devices/me/commands", null),
            (HttpMethod.Post, "/api/devices/me/commands/1/ack", new { }),
            (HttpMethod.Put, "/api/devices/me/status", new { policyVersion = 0, isPaused = false, studyActive = false }),
            (HttpMethod.Post, "/api/devices/me/requests", new { kind = "study_done" }),
            (HttpMethod.Get, "/api/devices/me/requests/1", null),
            (HttpMethod.Post, "/api/devices/me/apps", new { apps = new[] { new { packageName = "com.a.b", label = "A" } } }),
            (HttpMethod.Get, "/api/devices/me/apps/decisions", null),
            (HttpMethod.Post, "/api/devices/me/locations", new { points = new[] { new { lat = 1, lng = 1, accuracy = 1, time = now } } }),
            (HttpMethod.Post, "/api/devices/me/usage", new { days = new[] { new { date = DateTime.UtcNow.ToString("yyyy-MM-dd"), totalMinutes = 1, blocks = 0, apps = new Dictionary<string, int>() } } }),
            (HttpMethod.Post, "/api/devices/me/alerts", new { kind = "time_changed" }),
            (HttpMethod.Get, "/api/devices/me/geofences", null),
            (HttpMethod.Post, "/api/devices/me/geofence-events", new { events = Array.Empty<object>() }),
        };
        foreach (var (method, url, body) in calls)
            await Expect(HttpStatusCode.Unauthorized, kid.Send(method, url, body), $"{method} {url} sau khi hủy ghép");

        // Mẹ không còn thấy máy đã hủy; hủy lần hai là 404; nhưng mã ghép mới vẫn tạo được máy con mới độc lập.
        Assert.Equal(0, await Api.Count(await mom.Get("/api/devices")));
        await Expect(HttpStatusCode.NotFound, mom.Delete(kid.Url()));
        await Expect(HttpStatusCode.NotFound, mom.Get(kid.Url("/policy")));
        var kid2 = await mom.PairKid("Con 2");
        await Expect(HttpStatusCode.OK, kid2.Get("/api/devices/me"));
        await Expect(HttpStatusCode.Unauthorized, kid.Get("/api/devices/me"));
    }

    // ---- Token giả / hết hạn / sai vai trò ----

    [Fact]
    public async Task ForgedExpiredOrWrongKeyToken_Is401()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var expired = Tokens.Make("parent", 1, mom.FamilyId, TimeSpan.FromHours(-2));
        var wrongKey = Tokens.Make("parent", 1, mom.FamilyId, TimeSpan.FromHours(1), key: "another-key-another-key-another-key-123456");
        var wrongAudience = Tokens.Make("parent", 1, mom.FamilyId, TimeSpan.FromHours(1), audience: "ai-khac");
        var wrongIssuer = Tokens.Make("parent", 1, mom.FamilyId, TimeSpan.FromHours(1), issuer: "ai-khac");
        foreach (var t in new[] { expired, wrongKey, wrongAudience, wrongIssuer, "abc.def.ghi", "khong-phai-jwt" })
        {
            await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/devices", t), "token giả trên route mẹ");
            await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/devices/me", t), "token giả trên route con");
        }
        var expiredDevice = Tokens.Make("device", kid.Id, mom.FamilyId, TimeSpan.FromHours(-2));
        await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/devices/me", expiredDevice));
    }

    [Fact]
    public async Task ParentTokenForgedForOtherFamily_CannotReadDevice()
    {
        // Token ký đúng khóa nhưng gia đình trong token không phải chủ máy con: vẫn 404 (phân quyền dựa vào fam trong token).
        var a = await Api.NewMother();
        var kid = await a.PairKid();
        var b = await Api.NewMother();
        var bToken = Tokens.Make("parent", 1, b.FamilyId, TimeSpan.FromHours(1));
        await Expect(HttpStatusCode.NotFound, Api.Get(kid.Url("/policy"), bToken));
    }

    [Fact]
    public async Task WrongRole_Is403_AndNoToken_Is401()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Expect(HttpStatusCode.Forbidden, Api.Get("/api/devices", kid.Token), "token con trên route mẹ");
        await Expect(HttpStatusCode.Forbidden, Api.Get(kid.Url("/policy"), kid.Token));
        await Expect(HttpStatusCode.Forbidden, Api.Put("/api/requests/1", kid.Token, new { decision = "approved" }));
        await Expect(HttpStatusCode.Forbidden, Api.Post("/api/alerts/1/read", kid.Token));
        await Expect(HttpStatusCode.Forbidden, Api.Get("/api/devices/me", mom.Access), "token mẹ trên route con");
        await Expect(HttpStatusCode.Forbidden, Api.Get("/api/devices/me/policy", mom.Access));
        await Expect(HttpStatusCode.Forbidden, Api.Post("/api/devices/me/alerts", mom.Access, new { kind = "time_changed" }));

        await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/devices"));
        await Expect(HttpStatusCode.Unauthorized, Api.Get(kid.Url("/status")));
        await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/devices/me"));
        await Expect(HttpStatusCode.Unauthorized, Api.Put("/api/requests/1", null, new { decision = "approved" }));
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/alerts/1/read", null));
    }

    [Fact]
    public async Task DeviceMe_DoesNotLeakParentEmail()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var body = await (await kid.Get("/api/devices/me")).Content.ReadAsStringAsync();
        Assert.DoesNotContain(mom.Email, body);
        Assert.DoesNotContain("email", body, StringComparison.OrdinalIgnoreCase);
    }
}
