using System.Net;
using System.Text;
using System.Text.Json;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>Kiểm kiểu / độ dài / số lượng từng nhóm endpoint: sai thì 400, đúng ở mép giới hạn thì thành công.</summary>
public class ValidationTests(SharedApi shared) : TestBase(shared)
{
    async Task<(Mother Mom, Kid Kid)> World()
    {
        var mom = await Api.NewMother();
        return (mom, await mom.PairKid());
    }

    static string Today(int offsetDays = 0) => DateTime.UtcNow.AddDays(offsetDays).ToString("yyyy-MM-dd");

    static string PolicyBody(string json, object version) => JsonSerializer.Serialize(new { json, expectedVersion = version });

    // ---------------- Policy ----------------

    [Fact]
    public async Task Policy_Rejects_BadShapes()
    {
        var (mom, kid) = await World();
        var url = kid.Url("/policy");
        var bodies = new[]
        {
            PolicyBody("không phải json", 0),
            PolicyBody("[1,2]", 0),
            PolicyBody("123", 0),
            PolicyBody("\"chuoi\"", 0),
            PolicyBody("null", 0),
            PolicyBody("", 0),
            """{"expectedVersion":0}""",                   // thiếu json
            """{"json":{"a":1},"expectedVersion":0}""",    // json phải là chuỗi
            """{"json":"{}","expectedVersion":"x"}""",     // sai kiểu phiên bản
            """{"json":null,"expectedVersion":0}""",
            "khong phai json",
            "",
        };
        foreach (var b in bodies)
            await Expect(HttpStatusCode.BadRequest, mom.Api.Send(HttpMethod.Put, url, mom.Access, b), $"body: {b}");
        Assert.Equal(0, (await Api.Json(await mom.Get(url))).GetProperty("version").GetInt32());
    }

    [Fact]
    public async Task Policy_Size_IsMeasuredInBytes_Max64KiB()
    {
        var (mom, kid) = await World();
        var url = kid.Url("/policy");
        string Obj(int totalBytes) => "{\"x\":\"" + Pad(totalBytes - 8) + "\"}"; // 8 byte khung: {"x":""}

        await Expect(HttpStatusCode.OK, mom.Api.Send(HttpMethod.Put, url, mom.Access, PolicyBody(Obj(65536), 0)), "đúng 64 KiB");
        await Expect(HttpStatusCode.BadRequest, mom.Api.Send(HttpMethod.Put, url, mom.Access, PolicyBody(Obj(65537), 1)), "64 KiB + 1");
        // 30000 ký tự tiếng Việt 3 byte = 90000 byte: ít ký tự nhưng vượt trần byte.
        var multibyte = "{\"x\":\"" + new string('ế', 30000) + "\"}";
        await Expect(HttpStatusCode.BadRequest, mom.Api.Send(HttpMethod.Put, url, mom.Access, PolicyBody(multibyte, 1)), "đa byte");
        Assert.Equal(1, (await Api.Json(await mom.Get(url))).GetProperty("version").GetInt32());
    }

    // ---------------- Lệnh (commands) ----------------

    [Theory]
    [InlineData("pause", """{"minutes":0}""", true)]
    [InlineData("pause", """{"minutes":1440}""", true)]
    [InlineData("pause", "{}", true)]
    [InlineData("pause", """{"minutes":-1}""", false)]
    [InlineData("pause", """{"minutes":1441}""", false)]
    [InlineData("pause", """{"minutes":"5"}""", false)]
    [InlineData("pause", """{"minutes":1.5}""", false)]
    [InlineData("lock", """{"minutes":1}""", true)]
    [InlineData("lock", """{"minutes":0}""", false)]
    [InlineData("study_start", """{"minutes":60}""", true)]
    [InlineData("study_start", """{"minutes":null}""", false)]
    [InlineData("unpause", "{}", true)]
    [InlineData("unlock", "{}", true)]
    [InlineData("study_stop", "{}", true)]
    [InlineData("disable_limit_today", "{}", true)]
    [InlineData("enable_limit_today", "{}", true)]
    [InlineData("app_unlock_temp", """{"package":"com.a.b","minutes":240}""", true)]
    [InlineData("app_unlock_temp", """{"package":"com.a.b","minutes":241}""", false)]
    [InlineData("app_unlock_temp", """{"package":"com.a.b","minutes":0}""", false)]
    [InlineData("app_unlock_temp", """{"package":"com.a.b"}""", false)]
    [InlineData("app_unlock_temp", """{"minutes":5}""", false)]
    [InlineData("app_unlock_temp", """{"package":"khongcodau","minutes":5}""", false)]
    [InlineData("app_unlock_temp", """{"package":"1a.b","minutes":5}""", false)]
    [InlineData("app_unlock_temp", """{"package":123,"minutes":5}""", false)]
    [InlineData("app_block", """{"package":"com.a.b"}""", true)]
    [InlineData("app_block", """{"package":"com.a b"}""", false)]
    [InlineData("app_allow", "{}", false)]
    [InlineData("app_relock", """{"package":null}""", false)]
    [InlineData("extra_time_grant", """{"minutes":120}""", true)]
    [InlineData("extra_time_grant", """{"minutes":121}""", false)]
    [InlineData("extra_time_grant", """{"minutes":0}""", false)]
    [InlineData("khong_co_lenh_nay", "{}", false)]
    [InlineData("PAUSE", "{}", false)]
    [InlineData("", "{}", false)]
    [InlineData("pause", "[1]", false)]
    [InlineData("pause", "khong phai json", false)]
    public async Task Commands_Validate(string type, string payload, bool ok)
    {
        var (mom, kid) = await World();
        await Expect(ok ? HttpStatusCode.OK : HttpStatusCode.BadRequest,
            mom.Post(kid.Url("/commands"), new { type, payloadJson = payload }), $"{type} {payload}");
        Assert.Equal(ok ? 1 : 0, await Api.Count(await mom.Get(kid.Url("/commands"))));
    }

    [Fact]
    public async Task Commands_FieldLimits()
    {
        var (mom, kid) = await World();
        var url = kid.Url("/commands");
        await Expect(HttpStatusCode.BadRequest, mom.Post(url, new { type = Pad(51) }), "type 51 ký tự");
        await Expect(HttpStatusCode.BadRequest, mom.Post(url, """{"payloadJson":"{}"}"""), "thiếu type");
        await Expect(HttpStatusCode.BadRequest, mom.Post(url, """{"type":5}"""), "type sai kiểu");
        await Expect(HttpStatusCode.BadRequest, mom.Post(url, """{"type":"pause","payloadJson":{"minutes":5}}"""), "payloadJson phải là chuỗi");
        var big = "{\"minutes\":5,\"x\":\"" + Pad(4 * 1024) + "\"}";
        await Expect(HttpStatusCode.BadRequest, mom.Post(url, new { type = "pause", payloadJson = big }), "payload > 4 KiB");
        await Expect(HttpStatusCode.OK, mom.Post(url, new { type = "unpause" }), "bỏ trống payload");
        Assert.Equal(1, await Api.Count(await mom.Get(url)));
    }

    // ---------------- Yêu cầu của con ----------------

    [Theory]
    [InlineData("extra_time", """{"minutes":1}""", true)]
    [InlineData("extra_time", """{"minutes":240}""", true)]
    [InlineData("extra_time", """{"minutes":0}""", false)]
    [InlineData("extra_time", """{"minutes":241}""", false)]
    [InlineData("extra_time", """{"minutes":1.5}""", false)]
    [InlineData("extra_time", """{"minutes":"10"}""", false)]
    [InlineData("extra_time", """{"minutes":10,"app":"com.a.b"}""", false)]   // không cho lọt trường thừa
    [InlineData("extra_time", """{"app":"com.a.b"}""", false)]
    [InlineData("extra_time", "{}", false)]
    [InlineData("extra_time", null, false)]
    [InlineData("extra_time", "[10]", false)]
    [InlineData("extra_time", "khong phai json", false)]
    [InlineData("study_done", "{}", true)]
    [InlineData("study_done", null, true)]
    [InlineData("study_done", """{"minutes":5}""", false)]
    [InlineData("study_done", "[]", false)]
    [InlineData("homework", "{}", false)]
    [InlineData("EXTRA_TIME", """{"minutes":5}""", false)]
    [InlineData("", "{}", false)]
    public async Task ChildRequests_Validate(string kind, string? payload, bool ok)
    {
        var (mom, kid) = await World();
        await Expect(ok ? HttpStatusCode.OK : HttpStatusCode.BadRequest,
            kid.Post("/api/devices/me/requests", new { kind, payloadJson = payload }), $"{kind} {payload}");
        Assert.Equal(ok ? 1 : 0, await Api.Count(await mom.Get(kid.Url("/requests"))));
    }

    [Fact]
    public async Task ChildRequests_FieldLimits()
    {
        var (mom, kid) = await World();
        await Expect(HttpStatusCode.BadRequest, kid.Post("/api/devices/me/requests", new { kind = Pad(21) }), "kind 21 ký tự");
        await Expect(HttpStatusCode.BadRequest, kid.Post("/api/devices/me/requests", "{}"), "thiếu kind");
        await Expect(HttpStatusCode.BadRequest, kid.Post("/api/devices/me/requests", new { kind = "study_done", payloadJson = "{\"x\":\"" + Pad(300) + "\"}" }), "payload > 256 byte");
        await Expect(HttpStatusCode.BadRequest, mom.Get(kid.Url("/requests?status=bogus")), "status lọc sai");
        await Expect(HttpStatusCode.OK, mom.Get(kid.Url("/requests?status=pending")));
    }

    [Fact]
    public async Task ChildRequests_PerDeviceCap_Is429()
    {
        var (_, kid) = await World();
        // Đã quyết định/hết hạn không tính vào trần; 200 yêu cầu còn hiệu lực cùng lúc chỉ đạt được bằng cách ghi thẳng CSDL.
        await Factory.WithDb(async db =>
        {
            for (var i = 0; i < 200; i++)
                db.ChildRequests.Add(new Data.ChildRequest { DeviceId = kid.Id, Kind = "study_done", Payload = "{}", Status = "approved", CreatedAt = DateTime.UtcNow });
            await db.SaveChangesAsync();
        });
        await Expect(HttpStatusCode.TooManyRequests, kid.Post("/api/devices/me/requests", new { kind = "study_done" }));
    }

    [Fact]
    public async Task DecideRequest_Validates()
    {
        var (mom, kid) = await World();
        var extra = await kid.SeedRequest(30);
        var done = (await Api.Json(await kid.Post("/api/devices/me/requests", new { kind = "study_done" }))).GetProperty("id").GetInt32();

        await Expect(HttpStatusCode.BadRequest, mom.Put($"/api/requests/{extra}", new { decision = "maybe" }), "decision lạ");
        await Expect(HttpStatusCode.BadRequest, mom.Put($"/api/requests/{extra}", "{}"), "thiếu decision");
        await Expect(HttpStatusCode.BadRequest, mom.Put($"/api/requests/{extra}", new { decision = Pad(11) }), "decision quá dài");
        await Expect(HttpStatusCode.BadRequest, mom.Put($"/api/requests/{extra}", new { decision = "approved", minutes = 0 }), "0 phút");
        await Expect(HttpStatusCode.BadRequest, mom.Put($"/api/requests/{extra}", new { decision = "approved", minutes = 121 }), "121 phút");
        await Expect(HttpStatusCode.BadRequest, mom.Put($"/api/requests/{extra}", new { decision = "rejected", minutes = 5 }), "minutes khi từ chối");
        await Expect(HttpStatusCode.BadRequest, mom.Put($"/api/requests/{done}", new { decision = "approved", minutes = 5 }), "minutes cho study_done");
        // Mọi lần lỗi trên không được làm đổi trạng thái.
        Assert.Equal(2, (await Api.Json(await mom.Get(kid.Url("/requests?status=pending")))).GetArrayLength());

        await Expect(HttpStatusCode.NotFound, mom.Put("/api/requests/999999999", new { decision = "approved" }));
        var ok = await Api.Json(await mom.Put($"/api/requests/{extra}", new { decision = "approved", minutes = 120 }));
        Assert.Equal("approved", ok.GetProperty("status").GetString());
        var grant = (await Api.Json(await mom.Get(kid.Url("/commands")))).EnumerateArray().Single(c => c.GetProperty("type").GetString() == "extra_time_grant");
        Assert.Contains("120", grant.GetProperty("payloadJson").GetString());
    }

    // ---------------- App ----------------

    [Theory]
    [InlineData("com.a.b", "Ten", null, true)]
    [InlineData("com.a.b", "Ten", true, true)]
    [InlineData("khongcodau", "Ten", null, false)]
    [InlineData("1com.a", "Ten", null, false)]
    [InlineData("com.a b", "Ten", null, false)]
    [InlineData("com..", "Ten", null, false)]
    [InlineData("", "Ten", null, false)]
    [InlineData("com.a.b", "", null, false)]
    public async Task PostApps_Validate(string package, string label, bool? isNew, bool ok)
    {
        var (_, kid) = await World();
        await Expect(ok ? HttpStatusCode.NoContent : HttpStatusCode.BadRequest,
            kid.Post("/api/devices/me/apps", new { apps = new[] { new { packageName = package, label, isNew } } }));
    }

    [Fact]
    public async Task PostApps_FieldLimits()
    {
        var (mom, kid) = await World();
        var url = "/api/devices/me/apps";
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, "{}"), "thiếu apps");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"apps":null}"""));
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"apps":[null]}"""), "phần tử null");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"apps":[{"packageName":"com.a.b","label":"x","isNew":"yes"}]}"""), "isNew sai kiểu");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"apps":[{"label":"x"}]}"""), "thiếu packageName");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { apps = new[] { new { packageName = "com.a.b", label = Pad(201) } } }), "nhãn 201 ký tự");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { apps = new[] { new { packageName = "com." + Pad(253), label = "x" } } }), "gói > 256");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { apps = new[] { new { packageName = "com." + Pad(200), label = "x" } } }), "gói > 200 (qua được DTO, bị quy tắc chặn)");
        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { apps = new[] { new { packageName = "com." + Pad(196), label = Pad(200) } } }), "gói 200 + nhãn 200");
        var many = Enumerable.Range(0, 2001).Select(i => new { packageName = $"com.many.a{i}", label = "x" });
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { apps = many }), "2001 app trong một lô");
        Assert.Equal(1, await Api.Count(await mom.Get(kid.Url("/apps"))));
    }

    [Fact]
    public async Task PostApps_DeviceCap2000_Is429()
    {
        var (_, kid) = await World();
        var batch = Enumerable.Range(0, 2000).Select(i => new { packageName = $"com.cap.a{i}", label = "x" });
        await Expect(HttpStatusCode.NoContent, kid.Post("/api/devices/me/apps", new { apps = batch }), "đủ 2000");
        await Expect(HttpStatusCode.NoContent, kid.Post("/api/devices/me/apps", new { apps = new[] { new { packageName = "com.cap.a1", label = "doi nhan" } } }), "app đã có không tính thêm");
        await Expect(HttpStatusCode.TooManyRequests, kid.Post("/api/devices/me/apps", new { apps = new[] { new { packageName = "com.cap.thu2001", label = "x" } } }));
    }

    [Fact]
    public async Task Apps_ParentDecision_Validates()
    {
        var (mom, kid) = await World();
        await kid.SeedApp("com.seed.app");
        var ok = kid.Url("/apps/com.seed.app");
        await Expect(HttpStatusCode.BadRequest, mom.Put(ok, new { status = "new" }), "mẹ không đặt lại về new");
        await Expect(HttpStatusCode.BadRequest, mom.Put(ok, new { status = "deleted" }));
        await Expect(HttpStatusCode.BadRequest, mom.Put(ok, new { status = Pad(11) }));
        await Expect(HttpStatusCode.BadRequest, mom.Put(ok, "{}"));
        await Expect(HttpStatusCode.BadRequest, mom.Put(ok, """{"status":1}"""));
        await Expect(HttpStatusCode.BadRequest, mom.Put(kid.Url("/apps/khongcodau"), new { status = "blocked" }), "tên gói sai dạng");
        await Expect(HttpStatusCode.NotFound, mom.Put(kid.Url("/apps/com.chua.bao"), new { status = "blocked" }), "app chưa được con báo");
        await Expect(HttpStatusCode.BadRequest, mom.Get(kid.Url("/apps?status=bogus")));
        Assert.Equal("new", (await Api.Json(await mom.Get(kid.Url("/apps"))))[0].GetProperty("status").GetString());

        await Expect(HttpStatusCode.OK, mom.Put(ok, new { status = "blocked" }));
        var decisions = await Api.Json(await kid.Get("/api/devices/me/apps/decisions"));
        Assert.Equal("blocked", decisions[0].GetProperty("status").GetString());
        Assert.Equal(1, await Api.Count(await mom.Get(kid.Url("/apps?status=blocked"))));
    }

    [Fact]
    public async Task Apps_ChildCannotSelfApprove()
    {
        var (mom, kid) = await World();
        await kid.SeedApp("com.seed.app", isNew: true);
        // Trường "status" thừa trong body bị bỏ qua; gửi lại không cờ isNew không được đổi trạng thái chờ duyệt.
        await kid.Post("/api/devices/me/apps", """{"apps":[{"packageName":"com.seed.app","label":"Seed","status":"allowed"}]}""");
        Assert.Equal("new", (await Api.Json(await mom.Get(kid.Url("/apps"))))[0].GetProperty("status").GetString());
        Assert.Equal(0, await Api.Count(await kid.Get("/api/devices/me/apps/decisions")));
        // Mẹ chặn rồi, cài lại (isNew) thì phải duyệt lại.
        await mom.Put(kid.Url("/apps/com.seed.app"), new { status = "blocked" });
        await kid.SeedApp("com.seed.app", isNew: true);
        Assert.Equal("new", (await Api.Json(await mom.Get(kid.Url("/apps"))))[0].GetProperty("status").GetString());
    }

    // ---------------- Báo cáo sử dụng ----------------

    static object Day(string date, int total = 10, int blocks = 0, Dictionary<string, int>? apps = null) =>
        new { date, totalMinutes = total, blocks, apps = apps ?? new Dictionary<string, int> { ["com.a.b"] = 5 } };

    [Fact]
    public async Task PostUsage_Rejects_BadBatches()
    {
        var (mom, kid) = await World();
        var url = "/api/devices/me/usage";
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = Array.Empty<object>() }), "lô rỗng");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, "{}"), "thiếu days");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = Enumerable.Range(0, 32).Select(i => Day(Today(-i))) }), "32 ngày");
        foreach (var bad in new[] { "2026/10/31", "31-10-2026", "2026-1-5", "2026-13-01", "2026-02-30", "hôm nay", "", "2026-10-31T00:00:00" })
            await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(bad) } }), $"ngày '{bad}'");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(2)) } }), "ngày +2");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(-91)) } }), "ngày -91");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today()), Day(Today()) } }), "trùng ngày");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(), total: -1) } }), "tổng âm");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(), total: 1441) } }), "tổng 1441");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(), blocks: -1) } }), "blocks âm");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(), blocks: 10001) } }), "blocks 10001");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(), apps: new() { ["khongcodau"] = 1 }) } }), "gói sai dạng");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(), apps: new() { ["com.a.b"] = -1 }) } }), "phút app âm");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(), apps: new() { ["com.a.b"] = 1441 }) } }), "phút app 1441");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"days":[{"date":"2026-10-31","totalMinutes":1,"blocks":0}]}"""), "thiếu apps");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"days":[{"date":"2026-10-31","totalMinutes":"x","blocks":0,"apps":{}}]}"""), "tổng sai kiểu");
        var tooManyApps = Enumerable.Range(0, 201).ToDictionary(i => $"com.app.a{i}", _ => 1);
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { days = new[] { Day(Today(), apps: tooManyApps) } }), "201 app/ngày");
        // Không lô lỗi nào được ghi dở.
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url("/usage?from=" + Today(-89) + "&to=" + Today()))));
    }

    [Fact]
    public async Task PostUsage_Boundaries_Ok_AndResendOverwrites()
    {
        var (mom, kid) = await World();
        var url = "/api/devices/me/usage";
        var edge = Enumerable.Range(0, 200).ToDictionary(i => $"com.app.a{i}", _ => 1);
        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { days = new[] { Day(Today(), total: 1440, blocks: 10000, apps: edge) } }), "mép trên mọi giới hạn");
        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { days = new[] { Day(Today(1)) } }), "ngày mai (lệch múi giờ)");
        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { days = new[] { Day(Today(-90)) } }), "đúng 90 ngày trước");
        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { days = Enumerable.Range(0, 31).Select(i => Day(Today(-i - 10))) }), "đủ 31 ngày");

        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { days = new[] { Day(Today(), total: 7, apps: new() { ["com.x.y"] = 7 }) } }), "gửi lại cùng ngày");
        var today = (await Api.Json(await mom.Get(kid.Url($"/usage?from={Today()}&to={Today()}"))))[0];
        Assert.Equal(7, today.GetProperty("totalMinutes").GetInt32());
        Assert.Single(today.GetProperty("apps").EnumerateObject());
    }

    [Fact]
    public async Task GetUsage_QueryValidation()
    {
        var (mom, kid) = await World();
        await Expect(HttpStatusCode.OK, mom.Get(kid.Url("/usage")), "mặc định 7 ngày");
        await Expect(HttpStatusCode.BadRequest, mom.Get(kid.Url("/usage?from=2026-1-1")));
        await Expect(HttpStatusCode.BadRequest, mom.Get(kid.Url("/usage?to=khong")));
        await Expect(HttpStatusCode.BadRequest, mom.Get(kid.Url($"/usage?from={Today()}&to={Today(-1)}")), "from > to");
        await Expect(HttpStatusCode.BadRequest, mom.Get(kid.Url($"/usage?from={Today(-90)}&to={Today()}")), "91 ngày");
        await Expect(HttpStatusCode.OK, mom.Get(kid.Url($"/usage?from={Today(-89)}&to={Today()}")), "đúng 90 ngày");
        await Expect(HttpStatusCode.OK, mom.Get(kid.Url($"/usage?from={Today()}&to={Today()}")), "một ngày");
    }

    // ---------------- Trạng thái ----------------

    [Fact]
    public async Task PutStatus_Validates()
    {
        var (mom, kid) = await World();
        var url = "/api/devices/me/status";
        object Ok(object? battery = null, object? ver = null, object? perms = null, object? temp = null, object? paused = null, object? app = null) =>
            new Dictionary<string, object?>
            {
                ["batteryPercent"] = battery ?? 50, ["policyVersion"] = ver ?? 1, ["isPaused"] = paused ?? false,
                ["studyActive"] = false, ["permissionsMissing"] = perms ?? Array.Empty<string>(), ["appVersion"] = app ?? "1.0.0+1",
                ["tempUnlocked"] = temp ?? Array.Empty<object>(),
            };
        var soon = DateTime.UtcNow.AddMinutes(30);
        var bad = new (string Name, object Body)[]
        {
            ("pin 101", Ok(battery: 101)), ("pin -1", Ok(battery: -1)), ("pin chữ", Ok(battery: "abc")),
            ("phiên bản luật âm", Ok(ver: -1)), ("isPaused chuỗi", Ok(paused: "yes")),
            ("appVersion 33 ký tự", Ok(app: Pad(33, '1'))), ("appVersion ký tự lạ", Ok(app: "1.0 beta")),
            ("21 quyền", Ok(perms: Enumerable.Range(0, 21).Select(i => $"perm{i}").ToArray())),
            ("quyền viết hoa", Ok(perms: new[] { "Camera" })), ("quyền 41 ký tự", Ok(perms: new[] { Pad(41) })),
            ("quyền có khoảng trắng", Ok(perms: new[] { "a b" })),
            ("51 app mở tạm", Ok(temp: Enumerable.Range(0, 51).Select(i => new { package = $"com.t.a{i}", until = soon }).ToArray())),
            ("gói mở tạm sai", Ok(temp: new[] { new { package = "khongcodau", until = soon } })),
            ("thiếu hạn mở tạm", Ok(temp: new[] { new { package = "com.a.b", until = default(DateTime) } })),
            ("hạn mở tạm quá xa", Ok(temp: new[] { new { package = "com.a.b", until = DateTime.UtcNow.AddHours(10) } })),
        };
        foreach (var (name, body) in bad)
            await Expect(HttpStatusCode.BadRequest, kid.Put(url, body), name);
        Assert.Null((await Api.Json(await mom.Get(kid.Url("/status")))).GetProperty("reportedAt").GetString()); // lô lỗi không ghi gì

        var good = Ok(battery: 100, perms: Enumerable.Range(0, 20).Select(i => $"perm{i}").ToArray(),
            temp: Enumerable.Range(0, 50).Select(i => new { package = $"com.t.a{i}", until = DateTime.UtcNow.AddMinutes(239) }).ToArray(), app: Pad(32, '1'));
        await Expect(HttpStatusCode.NoContent, kid.Put(url, good), "mép trên mọi giới hạn");
        var s = await Api.Json(await mom.Get(kid.Url("/status")));
        Assert.Equal(100, s.GetProperty("batteryPercent").GetInt32());
        Assert.Equal(20, s.GetProperty("permissionsMissing").GetArrayLength());
        Assert.Equal(50, s.GetProperty("tempUnlocked").GetArrayLength());
    }

    [Fact]
    public async Task Status_BeforeFirstReport_IsEmptyDefaults()
    {
        var (mom, kid) = await World();
        var s = await Api.Json(await mom.Get(kid.Url("/status")));
        Assert.Equal(JsonValueKind.Null, s.GetProperty("reportedAt").ValueKind);
        Assert.Equal(0, s.GetProperty("policyVersion").GetInt32());
    }

    // ---------------- Cảnh báo ----------------

    [Theory]
    [InlineData("time_changed", null, true)]
    [InlineData("app_uninstall_attempt", "5", true)]
    [InlineData("accessibility_off", "-3", true)]
    [InlineData("device_admin_off", "abc_123", true)]
    [InlineData("permission_missing", "usage_access", true)]
    [InlineData("offline", null, false)]          // chỉ server tự tạo
    [InlineData("khong_co", null, false)]
    [InlineData("TIME_CHANGED", null, false)]
    [InlineData("", null, false)]
    [InlineData("time_changed", "Co Hoa", false)]  // chỉ mã/số ngắn
    [InlineData("time_changed", "com.zing.zalo", false)]
    [InlineData("time_changed", "a b", false)]
    [InlineData("time_changed", "ké", false)]
    [InlineData("time_changed", "--1", false)]
    public async Task PostAlert_Validate(string kind, string? detail, bool ok)
    {
        var (_, kid) = await World();
        await Expect(ok ? HttpStatusCode.OK : HttpStatusCode.BadRequest,
            kid.Post("/api/devices/me/alerts", new { kind, detail }), $"{kind} / {detail}");
    }

    [Fact]
    public async Task PostAlert_FieldLimits()
    {
        var (mom, kid) = await World();
        var url = "/api/devices/me/alerts";
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, "{}"), "thiếu kind");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { kind = Pad(31) }), "kind 31 ký tự");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"kind":"time_changed","detail":5}"""), "detail sai kiểu");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { kind = "time_changed", detail = Pad(33) }), "detail 33 ký tự");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { kind = "time_changed", occurredAt = DateTime.UtcNow.AddMinutes(10) }), "tương lai");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { kind = "time_changed", occurredAt = DateTime.UtcNow.AddDays(-8) }), "quá cũ");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"kind":"time_changed","occurredAt":"hôm qua"}"""), "thời điểm sai dạng");
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url("/alerts"))));
        await Expect(HttpStatusCode.OK, kid.Post(url, new { kind = "time_changed", detail = Pad(31), occurredAt = DateTime.UtcNow.AddDays(-6) }), "mép hợp lệ");
    }

    [Fact]
    public async Task Alerts_ListCap100_AndCursor()
    {
        var (mom, kid) = await World();
        var t0 = DateTime.UtcNow.AddDays(-6);
        for (var i = 0; i < 105; i++) // mỗi 11 phút để không bị coi là trùng
            await kid.SeedAlert("time_changed", t0.AddMinutes(i * 11));
        var newest = await Api.Json(await mom.Get(kid.Url("/alerts")));
        Assert.Equal(100, newest.GetArrayLength());
        var firstId = newest[0].GetProperty("id").GetInt32();
        var lastId = newest[99].GetProperty("id").GetInt32();
        Assert.True(lastId > firstId); // cũ trước, mới sau
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url($"/alerts?afterId={lastId}"))));
        Assert.Equal(5, await Api.Count(await mom.Get(kid.Url($"/alerts?afterId={lastId - 5}"))));
        await Expect(HttpStatusCode.BadRequest, mom.Get(kid.Url("/alerts?afterId=abc")));
    }

    [Fact]
    public async Task Alerts_MarkRead_IsIdempotent_AndUnknownIs404()
    {
        var (mom, kid) = await World();
        var id = await kid.SeedAlert();
        var first = await Api.Json(await mom.Post($"/api/alerts/{id}/read"));
        var readAt = first.GetProperty("readAt").GetString();
        Assert.NotNull(readAt);
        var second = await Api.Json(await mom.Post($"/api/alerts/{id}/read"));
        // Server trả cùng một thời điểm nhưng lần đầu có hậu tố Z, lần sau không (Kind của DateTime đọc từ CSDL): chỉ so thời điểm.
        Assert.Equal(readAt!.TrimEnd('Z'), second.GetProperty("readAt").GetString()!.TrimEnd('Z'));
        await Expect(HttpStatusCode.NotFound, mom.Post("/api/alerts/999999999/read"));
    }

    [Fact]
    public async Task OfflineAlert_ServerCreatesOnce_AndChildCannotForgeIt()
    {
        var (mom, kid) = await World();
        await Factory.WithDb(async db =>
        {
            db.Devices.Single(d => d.Id == kid.Id).LastSeenAt = DateTime.UtcNow.AddHours(-30);
            await db.SaveChangesAsync();
            Assert.Equal(1, await Services.OfflineAlerts.RunOnceAsync(db, DateTime.UtcNow, TimeSpan.FromHours(24)));
            Assert.Equal(0, await Services.OfflineAlerts.RunOnceAsync(db, DateTime.UtcNow, TimeSpan.FromHours(24)));
        });
        var list = await Api.Json(await mom.Get(kid.Url("/alerts")));
        Assert.Equal("offline", list[0].GetProperty("kind").GetString());
        Assert.Equal("30", list[0].GetProperty("detail").GetString());
    }

    // ---------------- Vị trí và hàng rào ----------------

    [Fact]
    public async Task PostLocations_Validates()
    {
        var (mom, kid) = await World();
        var url = "/api/devices/me/locations";
        var now = DateTime.UtcNow;
        object P(double lat = 10, double lng = 106, double acc = 5, object? time = null) => new { lat, lng, accuracy = acc, time = time ?? now };
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { points = new[] { P(lat: 91) } }), "lat 91");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { points = new[] { P(lat: -91) } }), "lat -91");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { points = new[] { P(lng: 181) } }), "lng 181");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { points = new[] { P(acc: -1) } }), "accuracy âm");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { points = new[] { P(acc: 100001) } }), "accuracy quá lớn");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"points":[{"lat":"x","lng":1,"accuracy":1,"time":"2026-10-31T00:00:00Z"}]}"""), "lat sai kiểu");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"points":[{"lat":1,"lng":1,"accuracy":1,"time":"hôm qua"}]}"""), "time sai dạng");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, "{}"), "thiếu points");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { points = Enumerable.Range(0, 501).Select(_ => P()).ToArray() }), "501 điểm");
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url("/locations"))));

        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { points = Enumerable.Range(0, 500).Select(_ => P(lat: 90, lng: -180, acc: 100000)).ToArray() }), "500 điểm mép");
        Assert.Equal(200, await Api.Count(await mom.Get(kid.Url("/locations")))); // mẹ chỉ nhận tối đa 200
    }

    [Fact]
    public async Task PostLocations_FutureAndOldPoints_AreDropped()
    {
        var (mom, kid) = await World();
        var now = DateTime.UtcNow;
        await Expect(HttpStatusCode.NoContent, kid.Post("/api/devices/me/locations", new
        {
            points = new[]
            {
                new { lat = 1.0, lng = 1.0, accuracy = 1.0, time = now.AddMinutes(30) },  // tương lai: bỏ
                new { lat = 2.0, lng = 2.0, accuracy = 1.0, time = now.AddDays(-30) },    // quá hạn giữ 7 ngày: xóa ngay lần gửi này
                new { lat = 3.0, lng = 3.0, accuracy = 1.0, time = now },
            },
        }));
        var pts = await Api.Json(await mom.Get(kid.Url("/locations")));
        Assert.Equal(1, pts.GetArrayLength());
        Assert.Equal(3.0, pts[0].GetProperty("lat").GetDouble());
    }

    [Fact]
    public async Task PutGeofences_Validates()
    {
        var (mom, kid) = await World();
        var url = kid.Url("/geofences");
        object F(string? name = "Nha", double lat = 10, double lng = 106, double r = 200, int id = 0) => new { id, name, lat, lng, radiusM = r };
        object Put(params object[] fences) => new { geofences = fences, expectedVersion = 0 };
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, Put(F(r: 99))), "bán kính 99");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, Put(F(r: 10001))), "bán kính 10001");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, Put(F(lat: 91))), "lat 91");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, Put(F(lng: -181))), "lng -181");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, Put(F(name: null))), "thiếu tên");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, Put(F(name: ""))), "tên rỗng");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, Put(F(name: Pad(101)))), "tên 101 ký tự");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, "{}"), "thiếu geofences");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, """{"geofences":[{"id":0,"name":"A","lat":"x","lng":1,"radiusM":200}],"expectedVersion":0}"""), "lat sai kiểu");
        await Expect(HttpStatusCode.BadRequest, mom.Put(url, new { geofences = Enumerable.Range(0, 101).Select(i => F(name: $"V{i}")).ToArray(), expectedVersion = 0 }), "101 vùng");
        Assert.Equal(0, (await Api.Json(await mom.Get(url))).GetProperty("version").GetInt32());

        await Expect(HttpStatusCode.OK, mom.Put(url, new { geofences = Enumerable.Range(0, 100).Select(i => F(name: $"V{i}", lat: 90, lng: 180, r: i % 2 == 0 ? 100 : 10000)).ToArray(), expectedVersion = 0 }), "100 vùng mép");
        Assert.Equal(100, (await Api.Json(await kid.Get("/api/devices/me/geofences"))).GetProperty("geofences").GetArrayLength());
    }

    [Fact]
    public async Task PostGeofenceEvents_Validates()
    {
        var (mom, kid) = await World();
        var fence = (await Api.Json(await mom.Put(kid.Url("/geofences"),
            new { geofences = new[] { new { id = 0, name = "Truong", lat = 10, lng = 106, radiusM = 150 } }, expectedVersion = 0 }))).GetProperty("geofences")[0].GetProperty("id").GetInt32();
        var url = "/api/devices/me/geofence-events";
        var now = DateTime.UtcNow;
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { events = new[] { new { geofenceId = fence, type = "x", time = now } } }), "type lạ");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { events = new[] { new { geofenceId = fence, type = "ENTER", time = now } } }), "type viết hoa");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"events":[{"geofenceId":1,"time":"2026-10-31T00:00:00Z"}]}"""), "thiếu type");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, """{"events":[{"geofenceId":"a","type":"enter","time":"2026-10-31T00:00:00Z"}]}"""), "id sai kiểu");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, "{}"), "thiếu events");
        await Expect(HttpStatusCode.BadRequest, kid.Post(url, new { events = Enumerable.Range(0, 201).Select(_ => new { geofenceId = fence, type = "enter", time = now }).ToArray() }), "201 sự kiện");
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url("/geofence-events"))));

        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { events = new[] { new { geofenceId = 999999999, type = "enter", time = now } } }), "vùng không tồn tại: bỏ qua");
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url("/geofence-events"))));
        await Expect(HttpStatusCode.NoContent, kid.Post(url, new { events = Enumerable.Range(0, 200).Select(_ => new { geofenceId = fence, type = "exit", time = now }).ToArray() }), "200 sự kiện mép");
        Assert.Equal(100, await Api.Count(await mom.Get(kid.Url("/geofence-events")))); // mẹ nhận tối đa 100 mỗi lượt
    }

    [Fact]
    public async Task GeofenceEvents_ChildCannotUseFenceOfAnotherDevice()
    {
        var mom = await Api.NewMother();
        var k1 = await mom.PairKid("Con 1");
        var k2 = await mom.PairKid("Con 2");
        var fence = (await Api.Json(await mom.Put(k1.Url("/geofences"),
            new { geofences = new[] { new { id = 0, name = "Truong", lat = 10, lng = 106, radiusM = 150 } }, expectedVersion = 0 }))).GetProperty("geofences")[0].GetProperty("id").GetInt32();
        await Expect(HttpStatusCode.NoContent, k2.Post("/api/devices/me/geofence-events", new { events = new[] { new { geofenceId = fence, type = "enter", time = DateTime.UtcNow } } }));
        Assert.Equal(0, await Api.Count(await mom.Get(k1.Url("/geofence-events"))));
        Assert.Equal(0, await Api.Count(await mom.Get(k2.Url("/geofence-events"))));
    }

    // ---------------- Chia sẻ vị trí ----------------

    [Theory]
    [InlineData("{}")]
    [InlineData("""{"enabled":null}""")]
    [InlineData("""{"enabled":"no"}""")]
    [InlineData("""{"enabled":"true"}""")]
    [InlineData("""{"enabled":1}""")]
    [InlineData("""{"enabled":[true]}""")]
    [InlineData("khong phai json")]
    [InlineData("")]
    public async Task LocationSharing_BadBody_Is400_AndFlagUnchanged(string body)
    {
        var (mom, kid) = await World();
        await Expect(HttpStatusCode.BadRequest, mom.Api.Send(HttpMethod.Put, kid.Url("/location-sharing"), mom.Access, body));
        Assert.True((await Api.Json(await mom.Get(kid.Url("/location-sharing")))).GetProperty("enabled").GetBoolean());
        Assert.True((await Api.Json(await kid.Get("/api/devices/me/settings"))).GetProperty("locationSharing").GetBoolean());
    }

    [Fact]
    public async Task LocationSharing_Off_Blocks_ChildUpload_AndParentReads_ButKeepsHistoryUntilDeleted()
    {
        var (mom, kid) = await World();
        var point = new { points = new[] { new { lat = 10.0, lng = 106.0, accuracy = 5.0, time = DateTime.UtcNow } } };
        await Expect(HttpStatusCode.NoContent, kid.Post("/api/devices/me/locations", point));
        await Expect(HttpStatusCode.OK, mom.Put(kid.Url("/location-sharing"), new { enabled = false }));

        await Expect(HttpStatusCode.Forbidden, kid.Post("/api/devices/me/locations", point), "con gửi khi đã tắt");
        var lastOff = await mom.Get(kid.Url("/location"));
        Assert.Equal(HttpStatusCode.Forbidden, lastOff.StatusCode);
        Assert.False((await Api.Json(lastOff)).GetProperty("locationSharing").GetBoolean());
        await Expect(HttpStatusCode.Forbidden, mom.Get(kid.Url("/locations")));

        await Expect(HttpStatusCode.OK, mom.Put(kid.Url("/location-sharing"), new { enabled = true }));
        Assert.Equal(1, await Api.Count(await mom.Get(kid.Url("/locations")))); // chỉ điểm gửi trước khi tắt
        await Expect(HttpStatusCode.NoContent, mom.Delete(kid.Url("/locations")));
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url("/locations"))));
        await Expect(HttpStatusCode.NoContent, mom.Get(kid.Url("/location")));
    }

    // ---------------- Đổi tên máy ----------------

    [Theory]
    [InlineData("Máy của Bin", "Máy của Bin")]
    [InlineData("  Có khoảng trắng  ", "Có khoảng trắng")]
    [InlineData("a", "a")]
    public async Task Rename_Ok_TrimsWhitespace(string input, string expected)
    {
        var (mom, kid) = await World();
        var r = await mom.Send(HttpMethod.Patch, kid.Url(), new { name = input });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        Assert.Equal(expected, (await Api.Json(r)).GetProperty("name").GetString());
        Assert.Equal(expected, (await Api.Json(await kid.Get("/api/devices/me"))).GetProperty("name").GetString());
    }

    [Fact]
    public async Task Rename_Max50_AndRejectsBadNames()
    {
        var (mom, kid) = await World();
        await Expect(HttpStatusCode.OK, mom.Send(HttpMethod.Patch, kid.Url(), new { name = Pad(50) }), "50 ký tự");
        await Expect(HttpStatusCode.BadRequest, mom.Send(HttpMethod.Patch, kid.Url(), new { name = "  " + Pad(50) + "  " }), "giới hạn 50 tính trên chuỗi thô, trước khi cắt khoảng trắng");
        var bad = new[] { """{"name":""}""", """{"name":"   "}""", """{"name":"a\nb"}""", """{"name":"a\tb"}""", """{"name":"a\u0000b"}""",
            """{"name":123}""", """{"name":null}""", "{}", "khong phai json", $$"""{"name":"{{Pad(51)}}"}""" };
        foreach (var b in bad)
            await Expect(HttpStatusCode.BadRequest, mom.Api.Send(HttpMethod.Patch, kid.Url(), mom.Access, b), $"body {b}");
        Assert.Equal(Pad(50), (await Api.Json(await kid.Get("/api/devices/me"))).GetProperty("name").GetString());
    }
}
