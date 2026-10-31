using System.Net;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>409: lệch phiên bản luật / hàng rào, quyết định hai lần, yêu cầu và cảnh báo trùng.</summary>
public class ConflictTests(SharedApi shared) : TestBase(shared)
{
    [Fact]
    public async Task Policy_StaleVersion_Is409_WithCurrentVersion_AndKeepsFirstWrite()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var v1 = await mom.Put(kid.Url("/policy"), new { json = """{"a":1}""", expectedVersion = 0 });
        Assert.Equal(HttpStatusCode.OK, v1.StatusCode);
        Assert.Equal(1, (await Api.Json(v1)).GetProperty("version").GetInt32());

        var stale = await mom.Put(kid.Url("/policy"), new { json = """{"a":2}""", expectedVersion = 0 });
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal(1, (await Api.Json(stale)).GetProperty("currentVersion").GetInt32());

        // Ghi từ phiên bản quá mới cũng lệch (không được "nhảy cóc").
        await Expect(HttpStatusCode.Conflict, mom.Put(kid.Url("/policy"), new { json = """{"a":3}""", expectedVersion = 5 }));

        var seen = await Api.Json(await kid.Get("/api/devices/me/policy"));
        Assert.Equal(1, seen.GetProperty("version").GetInt32());
        Assert.Equal("""{"a":1}""", seen.GetProperty("json").GetString());

        await Expect(HttpStatusCode.OK, mom.Put(kid.Url("/policy"), new { json = """{"a":4}""", expectedVersion = 1 }));
    }

    [Fact]
    public async Task Policy_BadJson_DoesNotBumpVersion()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Expect(HttpStatusCode.BadRequest, mom.Put(kid.Url("/policy"), new { json = "{khong", expectedVersion = 0 }));
        Assert.Equal(0, (await Api.Json(await mom.Get(kid.Url("/policy")))).GetProperty("version").GetInt32());
    }

    [Fact]
    public async Task Geofences_StaleVersion_Is409_AndKeepsFirstWrite()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var fence = new { id = 0, name = "Truong", lat = 10.77, lng = 106.7, radiusM = 150 };
        await Expect(HttpStatusCode.OK, mom.Put(kid.Url("/geofences"), new { geofences = new[] { fence }, expectedVersion = 0 }));

        var stale = await mom.Put(kid.Url("/geofences"), new { geofences = Array.Empty<object>(), expectedVersion = 0 });
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal(1, (await Api.Json(stale)).GetProperty("currentVersion").GetInt32());

        var now = await Api.Json(await mom.Get(kid.Url("/geofences")));
        Assert.Equal(1, now.GetProperty("version").GetInt32());
        Assert.Equal(1, now.GetProperty("geofences").GetArrayLength());
    }

    [Fact]
    public async Task Request_DecideTwice_Is409_AndOnlyOneCommand()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var id = await kid.SeedRequest(15);

        await Expect(HttpStatusCode.OK, mom.Put($"/api/requests/{id}", new { decision = "approved" }));
        var again = await mom.Put($"/api/requests/{id}", new { decision = "approved" });
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
        Assert.Equal("approved", (await Api.Json(again)).GetProperty("status").GetString());
        await Expect(HttpStatusCode.Conflict, mom.Put($"/api/requests/{id}", new { decision = "rejected" }));

        var cmds = await Api.Json(await mom.Get(kid.Url("/commands")));
        Assert.Equal(1, cmds.EnumerateArray().Count(c => c.GetProperty("type").GetString() == "extra_time_grant"));
    }

    [Fact]
    public async Task Request_Duplicate_Is409_WithExistingId_UntilDecided()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var id = await kid.SeedRequest(10);

        var dup = await kid.Post("/api/devices/me/requests", new { kind = "extra_time", payloadJson = """{"minutes":20}""" });
        Assert.Equal(HttpStatusCode.Conflict, dup.StatusCode);
        Assert.Equal(id, (await Api.Json(dup)).GetProperty("id").GetInt32());

        // Loại khác không bị coi là trùng.
        await Expect(HttpStatusCode.OK, kid.Post("/api/devices/me/requests", new { kind = "study_done" }));

        await Expect(HttpStatusCode.OK, mom.Put($"/api/requests/{id}", new { decision = "rejected" }));
        await Expect(HttpStatusCode.OK, kid.Post("/api/devices/me/requests", new { kind = "extra_time", payloadJson = """{"minutes":20}""" }));
    }

    [Fact]
    public async Task Request_Expired_CannotBeDecided_Is409_AndIsHidden()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var id = await kid.SeedRequest(10);
        await Factory.WithDb(async db =>
        {
            db.ChildRequests.Single(r => r.Id == id).CreatedAt = DateTime.UtcNow.AddHours(-25);
            await db.SaveChangesAsync();
        });
        await Expect(HttpStatusCode.Conflict, mom.Put($"/api/requests/{id}", new { decision = "approved" }));
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url("/requests"))));
        // Con được gửi lại yêu cầu mới sau khi cái cũ hết hạn.
        await Expect(HttpStatusCode.OK, kid.Post("/api/devices/me/requests", new { kind = "extra_time", payloadJson = """{"minutes":10}""" }));
    }

    [Fact]
    public async Task Alert_SameKindWithin10Minutes_Is409_WithExistingId()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var id = await kid.SeedAlert("time_changed");

        var dup = await kid.Post("/api/devices/me/alerts", new { kind = "time_changed" });
        Assert.Equal(HttpStatusCode.Conflict, dup.StatusCode);
        Assert.Equal(id, (await Api.Json(dup)).GetProperty("id").GetInt32());

        await Expect(HttpStatusCode.OK, kid.Post("/api/devices/me/alerts", new { kind = "device_admin_off" }), "loại khác");
        await Expect(HttpStatusCode.OK, kid.Post("/api/devices/me/alerts", new { kind = "time_changed", occurredAt = DateTime.UtcNow.AddMinutes(-30) }), "cách >10 phút");
        Assert.Equal(3, await Api.Count(await mom.Get(kid.Url("/alerts"))));
    }
}
