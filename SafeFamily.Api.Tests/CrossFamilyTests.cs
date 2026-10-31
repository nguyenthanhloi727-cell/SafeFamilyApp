using System.Net;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>
/// Phân quyền chéo gia đình: mẹ B không đọc/ghi được máy con của mẹ A trên MỌI nhóm endpoint phía mẹ (kỳ vọng 404,
/// không phải 403 để không lộ máy tồn tại). Mỗi ca dựng thế giới mới: A có máy con đã có app, yêu cầu, cảnh báo;
/// đối chứng mẹ A gọi cùng đường dẫn phải thành công (để chắc 404 là do khác gia đình chứ không phải do sai đường dẫn).
/// </summary>
public class CrossFamilyTests(SharedApi shared) : TestBase(shared)
{
    // {id} máy con, {pkg} gói app đã báo, {req} yêu cầu, {alert} cảnh báo.
    public static TheoryData<string, string, string?> Routes => new()
    {
        { "PATCH", "/api/devices/{id}", """{"name":"Ten moi"}""" },
        { "GET", "/api/devices/{id}/policy", null },
        { "PUT", "/api/devices/{id}/policy", """{"json":"{}","expectedVersion":0}""" },
        { "GET", "/api/devices/{id}/apps", null },
        { "PUT", "/api/devices/{id}/apps/{pkg}", """{"status":"blocked"}""" },
        { "POST", "/api/devices/{id}/commands", """{"type":"pause","payloadJson":"{\"minutes\":5}"}""" },
        { "GET", "/api/devices/{id}/commands", null },
        { "GET", "/api/devices/{id}/status", null },
        { "GET", "/api/devices/{id}/requests", null },
        { "GET", "/api/devices/{id}/usage", null },
        { "GET", "/api/devices/{id}/alerts", null },
        { "GET", "/api/devices/{id}/location-sharing", null },
        { "PUT", "/api/devices/{id}/location-sharing", """{"enabled":false}""" },
        { "DELETE", "/api/devices/{id}/locations", null },
        { "GET", "/api/devices/{id}/location", null },
        { "GET", "/api/devices/{id}/locations", null },
        { "GET", "/api/devices/{id}/geofences", null },
        { "PUT", "/api/devices/{id}/geofences", """{"geofences":[],"expectedVersion":0}""" },
        { "GET", "/api/devices/{id}/geofence-events", null },
        { "PUT", "/api/requests/{req}", """{"decision":"rejected"}""" },
        { "POST", "/api/alerts/{alert}/read", null },
    };

    sealed record World(Mother Mom, Kid Kid, string Pkg, int Req, int Alert)
    {
        public string Fill(string path) => path.Replace("{id}", Kid.Id.ToString()).Replace("{pkg}", Pkg)
            .Replace("{req}", Req.ToString()).Replace("{alert}", Alert.ToString());
    }

    async Task<World> NewWorld()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await kid.SeedApp("com.seed.app");
        return new World(mom, kid, "com.seed.app", await kid.SeedRequest(), await kid.SeedAlert());
    }

    [Theory, MemberData(nameof(Routes))]
    public async Task MotherB_CannotTouchMotherAsDevice_Gets404(string method, string path, string? body)
    {
        var a = await NewWorld();
        var b = await Api.NewMother();
        var url = a.Fill(path);
        var m = new HttpMethod(method);

        await Expect(HttpStatusCode.NotFound, b.Send(m, url, body), $"mẹ B {method} {url}");

        var control = await a.Mom.Send(m, url, body);
        Assert.True(control.IsSuccessStatusCode,
            $"đối chứng mẹ A {method} {url} phải thành công, nhận {(int)control.StatusCode}: {await control.Content.ReadAsStringAsync()}");
    }

    [Fact]
    public async Task MotherB_CannotUnpairOrSeeDevice_AndDeviceStaysPaired()
    {
        var a = await NewWorld();
        var b = await Api.NewMother();

        await Expect(HttpStatusCode.NotFound, b.Delete(a.Kid.Url()));
        var list = await Api.Json(await b.Get("/api/devices"));
        Assert.Equal(0, list.GetArrayLength());
        await Expect(HttpStatusCode.OK, a.Kid.Get("/api/devices/me")); // máy con vẫn dùng được token
    }

    [Fact]
    public async Task MotherB_Writes_ChangeNothing()
    {
        var a = await NewWorld();
        var b = await Api.NewMother();

        await b.Send(HttpMethod.Patch, a.Kid.Url(), new { name = "Hacked" });
        await b.Put(a.Kid.Url("/policy"), new { json = "{\"x\":1}", expectedVersion = 0 });
        await b.Put(a.Kid.Url($"/apps/{a.Pkg}"), new { status = "blocked" });
        await b.Post(a.Kid.Url("/commands"), new { type = "pause", payloadJson = "{}" });
        await b.Put(a.Kid.Url("/location-sharing"), new { enabled = false });
        await b.Delete(a.Kid.Url("/locations"));
        await b.Put(a.Kid.Url("/geofences"), new { geofences = new[] { new { id = 0, name = "x", lat = 1, lng = 1, radiusM = 200 } }, expectedVersion = 0 });
        await b.Put($"/api/requests/{a.Req}", new { decision = "approved", minutes = 5 });
        await b.Post($"/api/alerts/{a.Alert}/read");

        var name = (await Api.Json(await a.Mom.Get("/api/devices")))[0].GetProperty("name").GetString();
        Assert.Equal("Con", name);
        Assert.Equal(0, (await Api.Json(await a.Mom.Get(a.Kid.Url("/policy")))).GetProperty("version").GetInt32());
        Assert.Equal("new", (await Api.Json(await a.Mom.Get(a.Kid.Url("/apps"))))[0].GetProperty("status").GetString());
        Assert.Equal(0, await Api.Count(await a.Mom.Get(a.Kid.Url("/commands"))));
        Assert.True((await Api.Json(await a.Mom.Get(a.Kid.Url("/location-sharing")))).GetProperty("enabled").GetBoolean());
        Assert.Equal(0, (await Api.Json(await a.Mom.Get(a.Kid.Url("/geofences")))).GetProperty("version").GetInt32());
        Assert.Equal("pending", (await Api.Json(await a.Mom.Get(a.Kid.Url("/requests"))))[0].GetProperty("status").GetString());
        Assert.Equal(System.Text.Json.JsonValueKind.Null, (await Api.Json(await a.Mom.Get(a.Kid.Url("/alerts"))))[0].GetProperty("readAt").ValueKind);
    }

    [Fact]
    public async Task ChildOfFamilyB_CannotReadRequestOfFamilyA()
    {
        var a = await NewWorld();
        var b = await Api.NewMother();
        var kidB = await b.PairKid();
        await Expect(HttpStatusCode.NotFound, kidB.Get($"/api/devices/me/requests/{a.Req}"));
        await Expect(HttpStatusCode.OK, a.Kid.Get($"/api/devices/me/requests/{a.Req}"));
    }

    [Fact]
    public async Task GeofenceIdOfAnotherDevice_IsNotUpdated()
    {
        var mom = await Api.NewMother();
        var k1 = await mom.PairKid("Con 1");
        var k2 = await mom.PairKid("Con 2");
        var put1 = await Api.Json(await mom.Put(k1.Url("/geofences"),
            new { geofences = new[] { new { id = 0, name = "Truong", lat = 10.7, lng = 106.7, radiusM = 150 } }, expectedVersion = 0 }));
        var fenceOfK1 = put1.GetProperty("geofences")[0].GetProperty("id").GetInt32();

        // Cùng gia đình nhưng máy khác: id hàng rào của máy 1 gửi vào máy 2 không được ghi đè hàng rào máy 1.
        var put2 = await Api.Json(await mom.Put(k2.Url("/geofences"),
            new { geofences = new[] { new { id = fenceOfK1, name = "Chiem", lat = 1, lng = 1, radiusM = 500 } }, expectedVersion = 0 }));
        Assert.NotEqual(fenceOfK1, put2.GetProperty("geofences")[0].GetProperty("id").GetInt32());

        var again = await Api.Json(await mom.Get(k1.Url("/geofences")));
        Assert.Equal("Truong", again.GetProperty("geofences")[0].GetProperty("name").GetString());
    }

    [Fact]
    public async Task MotherA_CanUseNewMotherOwnDevice_NotThePrevious()
    {
        // Hai gia đình, cùng id số khác nhau: id máy con của A thử trên B không rò dữ liệu qua danh sách.
        var a = await NewWorld();
        var b = await NewWorld();
        Assert.NotEqual(a.Kid.Id, b.Kid.Id);
        await Expect(HttpStatusCode.NotFound, a.Mom.Get(b.Kid.Url("/policy")));
        await Expect(HttpStatusCode.NotFound, b.Mom.Get(a.Kid.Url("/policy")));
    }
}
