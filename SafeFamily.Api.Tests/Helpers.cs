using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>Gọi API: body là object (gửi dạng JSON), hoặc string (gửi nguyên văn, để thử sai kiểu / sai dạng).</summary>
public class Api(ApiFactory factory)
{
    public ApiFactory Factory { get; } = factory;
    readonly HttpClient _http = factory.CreateClient();

    public async Task<HttpResponseMessage> Send(HttpMethod method, string url, string? token = null, object? body = null)
    {
        var req = new HttpRequestMessage(method, url);
        if (token is not null) req.Headers.Authorization = new("Bearer", token);
        if (body is string raw) req.Content = new StringContent(raw, Encoding.UTF8, "application/json");
        else if (body is not null) req.Content = JsonContent.Create(body);
        return await _http.SendAsync(req);
    }

    public Task<HttpResponseMessage> Get(string url, string? token = null) => Send(HttpMethod.Get, url, token);
    public Task<HttpResponseMessage> Post(string url, string? token, object? body = null) => Send(HttpMethod.Post, url, token, body ?? new { });
    public Task<HttpResponseMessage> Put(string url, string? token, object body) => Send(HttpMethod.Put, url, token, body);
    public Task<HttpResponseMessage> Delete(string url, string? token) => Send(HttpMethod.Delete, url, token);

    static int _seq;
    public static string UniqueEmail() => $"u{Interlocked.Increment(ref _seq)}.{Guid.NewGuid():N}@test.local";

    /// <summary>Đăng ký một mẹ mới (gia đình mới).</summary>
    public async Task<Mother> NewMother()
    {
        var email = UniqueEmail();
        var r = await Post("/api/auth/register", null, new { email, password = "password123", familyName = "Nha " + email[..6] });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var j = await Json(r);
        return new Mother(this, email, j.GetProperty("accessToken").GetString()!, j.GetProperty("refreshToken").GetString()!,
            j.GetProperty("familyId").GetInt32());
    }

    public static async Task<JsonElement> Json(HttpResponseMessage r) =>
        JsonDocument.Parse(await r.Content.ReadAsStringAsync()).RootElement.Clone();

    public static async Task<int> Count(HttpResponseMessage r) => (await Json(r)).GetArrayLength();
}

public class Mother(Api api, string email, string access, string refresh, int familyId)
{
    public Api Api { get; } = api;
    public string Email { get; } = email;
    public string Access { get; } = access;
    public string Refresh { get; } = refresh;
    public int FamilyId { get; } = familyId;

    /// <summary>Tạo mã ghép rồi cho một máy con nhận mã.</summary>
    public async Task<Kid> PairKid(string name = "Con")
    {
        var code = await NewCode(name);
        var r = await Api.Post("/api/pairing/claim", null, new { code });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var j = await Api.Json(r);
        return new Kid(Api, this, j.GetProperty("deviceToken").GetString()!, j.GetProperty("deviceId").GetInt32());
    }

    public async Task<string> NewCode(string name = "Con")
    {
        var r = await Api.Post("/api/pairing/code", Access, new { deviceName = name });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        return (await Api.Json(r)).GetProperty("code").GetString()!;
    }

    public Task<HttpResponseMessage> Get(string url) => Api.Get(url, Access);
    public Task<HttpResponseMessage> Post(string url, object? body = null) => Api.Post(url, Access, body);
    public Task<HttpResponseMessage> Put(string url, object body) => Api.Put(url, Access, body);
    public Task<HttpResponseMessage> Delete(string url) => Api.Delete(url, Access);
    public Task<HttpResponseMessage> Send(HttpMethod m, string url, object? body = null) => Api.Send(m, url, Access, body);
}

public class Kid(Api api, Mother mother, string token, int id)
{
    public Api Api { get; } = api;
    public Mother Mother { get; } = mother;
    public string Token { get; } = token;
    public int Id { get; } = id;
    public string Url(string tail = "") => $"/api/devices/{Id}{tail}";

    public Task<HttpResponseMessage> Get(string url) => Api.Get(url, Token);
    public Task<HttpResponseMessage> Post(string url, object? body = null) => Api.Post(url, Token, body);
    public Task<HttpResponseMessage> Put(string url, object body) => Api.Put(url, Token, body);
    public Task<HttpResponseMessage> Send(HttpMethod m, string url, object? body = null) => Api.Send(m, url, Token, body);

    /// <summary>Máy con báo một app mới cài.</summary>
    public async Task SeedApp(string package = "com.seed.app", bool isNew = true)
    {
        var r = await Post("/api/devices/me/apps", new { apps = new[] { new { packageName = package, label = "Seed", isNew } } });
        Assert.Equal(HttpStatusCode.NoContent, r.StatusCode);
    }

    /// <summary>Máy con gửi yêu cầu thêm giờ; trả về id yêu cầu.</summary>
    public async Task<int> SeedRequest(int minutes = 10)
    {
        var r = await Post("/api/devices/me/requests", new { kind = "extra_time", payloadJson = $"{{\"minutes\":{minutes}}}" });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        return (await Api.Json(r)).GetProperty("id").GetInt32();
    }

    /// <summary>Máy con báo một cảnh báo; trả về id.</summary>
    public async Task<int> SeedAlert(string kind = "time_changed", DateTime? at = null)
    {
        var r = await Post("/api/devices/me/alerts", new { kind, occurredAt = at });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        return (await Api.Json(r)).GetProperty("id").GetInt32();
    }
}

public static class Tokens
{
    /// <summary>Tự ký một JWT như server: để thử token hết hạn / sai khóa / sai vai trò.</summary>
    public static string Make(string role, int sub, int fam, TimeSpan life, string key = ApiFactory.JwtKey,
        string issuer = "SafeFamily.Api", string audience = "SafeFamily.App")
    {
        var creds = new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), SecurityAlgorithms.HmacSha256);
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(issuer, audience,
            [new Claim("sub", sub.ToString()), new Claim("fam", fam.ToString()), new Claim(ClaimTypes.Role, role)],
            notBefore: now.AddHours(-3), expires: now.Add(life), signingCredentials: creds);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
