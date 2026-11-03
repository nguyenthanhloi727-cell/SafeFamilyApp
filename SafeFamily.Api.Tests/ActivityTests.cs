using System.Net;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>T8: nhật ký hoạt động của máy con (POST /api/devices/me/activity, GET /api/devices/{id}/activity).</summary>
public class ActivityTests(SharedApi shared) : TestBase(shared)
{
    const string Url = "/api/devices/me/activity";

    static object Ev(string kind, string? detail = null, DateTime? at = null) =>
        new { kind, detail, occurredAt = at ?? DateTime.UtcNow.AddMinutes(-1) };

    [Fact]
    public async Task Batch_IsStored_AndMotherReadsItInOrder()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var t = DateTime.UtcNow.AddMinutes(-10);
        await Expect(HttpStatusCode.NoContent, kid.Post(Url, new
        {
            events = new[]
            {
                Ev("blocked_app_open", "com.google.android.youtube", t),
                Ev("parent_auth_failed", null, t.AddMinutes(1)),
                Ev("parent_unlocked", null, t.AddMinutes(2)),
            },
        }));

        var list = await Api.Json(await mom.Get(kid.Url("/activity")));
        Assert.Equal(3, list.GetArrayLength());
        Assert.Equal("blocked_app_open", list[0].GetProperty("kind").GetString());
        Assert.Equal("com.google.android.youtube", list[0].GetProperty("detail").GetString());
        Assert.Equal("parent_unlocked", list[2].GetProperty("kind").GetString());
        Assert.Equal(System.Text.Json.JsonValueKind.Null, list[1].GetProperty("detail").ValueKind);

        var lastId = list[1].GetProperty("id").GetInt32();
        var after = await Api.Json(await mom.Get(kid.Url($"/activity?afterId={lastId}")));
        Assert.Equal(1, after.GetArrayLength());
        Assert.Equal("parent_unlocked", after[0].GetProperty("kind").GetString());
    }

    [Theory]
    [InlineData("blocked_app_open", "com.zing.zalo", true)]
    [InlineData("blocked_app_open", "app_1.b2", true)]
    [InlineData("blocked_app_open", null, false)]            // thiếu tên gói
    [InlineData("blocked_app_open", "Co Hoa", false)]
    [InlineData("blocked_app_open", "com..a", false)]
    [InlineData("parent_auth_failed", null, true)]
    [InlineData("parent_auth_failed", "com.a.b", false)]     // loại này không có detail
    [InlineData("parent_unlocked", null, true)]
    [InlineData("khong_co", null, false)]
    [InlineData("PARENT_UNLOCKED", null, false)]
    [InlineData("", null, false)]
    public async Task Validate_KindAndDetail(string kind, string? detail, bool ok)
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Expect(ok ? HttpStatusCode.NoContent : HttpStatusCode.BadRequest,
            kid.Post(Url, new { events = new[] { Ev(kind, detail) } }), $"{kind} / {detail}");
        Assert.Equal(ok ? 1 : 0, await Api.Count(await mom.Get(kid.Url("/activity"))));
    }

    [Fact]
    public async Task Validate_BatchLimits_AndTimes()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Expect(HttpStatusCode.BadRequest, kid.Post(Url, "{}"), "thiếu events");
        await Expect(HttpStatusCode.BadRequest, kid.Post(Url, new { events = Array.Empty<object>() }), "lô rỗng");
        await Expect(HttpStatusCode.BadRequest, kid.Post(Url, new { events = Enumerable.Range(0, 51).Select(_ => Ev("parent_unlocked")).ToArray() }), "51 sự kiện");
        await Expect(HttpStatusCode.BadRequest, kid.Post(Url, new { events = new[] { Ev("parent_unlocked", null, DateTime.UtcNow.AddMinutes(10)) } }), "tương lai");
        await Expect(HttpStatusCode.BadRequest, kid.Post(Url, new { events = new[] { Ev("parent_unlocked", null, DateTime.UtcNow.AddDays(-31)) } }), "quá cũ");
        await Expect(HttpStatusCode.BadRequest, kid.Post(Url, new { events = new[] { Ev("blocked_app_open", Pad(101)) } }), "detail 101 ký tự");
        await Expect(HttpStatusCode.BadRequest, kid.Post(Url, """{"events":[{"kind":"parent_unlocked","occurredAt":"hôm qua"}]}"""), "thời điểm sai dạng");
        // một sự kiện sai làm hỏng cả lô, không lưu nửa chừng
        await Expect(HttpStatusCode.BadRequest, kid.Post(Url, new { events = new[] { Ev("parent_unlocked"), Ev("khong_co") } }));
        Assert.Equal(0, await Api.Count(await mom.Get(kid.Url("/activity"))));
        await Expect(HttpStatusCode.NoContent, kid.Post(Url, new { events = Enumerable.Range(0, 50).Select(_ => Ev("parent_unlocked")).ToArray() }), "50 sự kiện");
    }

    [Fact]
    public async Task OldRows_AreTrimmed_AndRowCountIsCapped()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Factory.WithDb(async db =>
        {
            var now = DateTime.UtcNow;
            db.ActivityEvents.Add(new ActivityEvent { DeviceId = kid.Id, Kind = "parent_unlocked", Time = now.AddDays(-31) });
            db.ActivityEvents.AddRange(Enumerable.Range(0, 1000).Select(_ =>
                new ActivityEvent { DeviceId = kid.Id, Kind = "parent_unlocked", Time = now.AddDays(-1) }));
            await db.SaveChangesAsync();
        });
        await Expect(HttpStatusCode.NoContent, kid.Post(Url, new { events = new[] { Ev("parent_auth_failed"), Ev("parent_auth_failed") } }));
        await Factory.WithDb(async db =>
        {
            Assert.Equal(1000, await db.ActivityEvents.CountAsync(a => a.DeviceId == kid.Id));
            Assert.Equal(2, await db.ActivityEvents.CountAsync(a => a.DeviceId == kid.Id && a.Kind == "parent_auth_failed"));
            Assert.Equal(0, await db.ActivityEvents.CountAsync(a => a.DeviceId == kid.Id && a.Time < DateTime.UtcNow.AddDays(-30)));
        });
    }

    [Fact]
    public async Task OtherFamily_Gets404_AndRolesAreEnforced()
    {
        var a = await Api.NewMother();
        var kid = await a.PairKid();
        var b = await Api.NewMother();
        await kid.Post(Url, new { events = new[] { Ev("parent_unlocked") } });

        await Expect(HttpStatusCode.NotFound, b.Get(kid.Url("/activity")));
        await Expect(HttpStatusCode.OK, a.Get(kid.Url("/activity")));
        await Expect(HttpStatusCode.Forbidden, a.Post(Url, new { events = new[] { Ev("parent_unlocked") } }), "mẹ không được gửi");
        await Expect(HttpStatusCode.Forbidden, kid.Get(kid.Url("/activity")), "máy con không được đọc");
        await Expect(HttpStatusCode.Unauthorized, Api.Post(Url, null, new { events = new[] { Ev("parent_unlocked") } }));
    }

    [Fact]
    public async Task RevokedDevice_CannotPost_AndMotherGets404()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Expect(HttpStatusCode.NoContent, mom.Delete(kid.Url()));
        await Expect(HttpStatusCode.Unauthorized, kid.Post(Url, new { events = new[] { Ev("parent_unlocked") } }));
        await Expect(HttpStatusCode.NotFound, mom.Get(kid.Url("/activity")));
    }
}
