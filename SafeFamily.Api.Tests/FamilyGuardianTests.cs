using System.Net;
using System.Text.Json;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>
/// API-02: người giám hộ thứ 2. Chủ mời bằng mã 8 số (30 phút, một lần), người được mời đăng ký vào cùng gia đình,
/// hai người thấy cùng danh sách máy con. Quyền ngang nhau trừ mời/xóa người giám hộ và xóa tài khoản gia đình.
/// </summary>
public class FamilyGuardianTests(SharedApi shared) : TestBase(shared)
{
    async Task<string> Invite(Mother owner)
    {
        var r = await owner.Post("/api/family/invite");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        return (await Api.Json(r)).GetProperty("code").GetString()!;
    }

    /// <summary>Chủ mời, bố đăng ký bằng mã. Trả về bố (cùng FamilyId với chủ).</summary>
    async Task<Mother> Dad(Mother owner)
    {
        var code = await Invite(owner);
        var email = Api.UniqueEmail();
        var r = await Api.Post("/api/family/join", null, new { code, email, password = "password123" });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var j = await Api.Json(r);
        Assert.Equal(owner.FamilyId, j.GetProperty("familyId").GetInt32());
        return new Mother(Api, email, j.GetProperty("accessToken").GetString()!, j.GetProperty("refreshToken").GetString()!, owner.FamilyId);
    }

    static async Task<int[]> DeviceIds(Mother m) =>
        (await Api.Json(await m.Get("/api/devices"))).EnumerateArray().Select(d => d.GetProperty("id").GetInt32()).Order().ToArray();

    [Fact]
    public async Task Invite_ThenJoin_BothSeeSameDevices()
    {
        var mom = await Api.NewMother();
        var kid1 = await mom.PairKid("Con 1");
        var dad = await Dad(mom);
        var kid2 = await dad.PairKid("Con 2"); // bố ghép thêm máy: mẹ cũng thấy
        var seenByMom = await DeviceIds(mom);
        Assert.Equal(new[] { kid1.Id, kid2.Id }.Order().ToArray(), seenByMom);
        Assert.Equal(seenByMom, await DeviceIds(dad));
    }

    [Fact]
    public async Task Family_ListsMembers_WithOwnerAndMe()
    {
        var mom = await Api.NewMother();
        var dad = await Dad(mom);
        foreach (var (who, ownerView) in new[] { (mom, true), (dad, false) })
        {
            var j = await Api.Json(await who.Get("/api/family"));
            Assert.Equal(ownerView, j.GetProperty("isOwner").GetBoolean());
            var members = j.GetProperty("members").EnumerateArray().ToList();
            Assert.Equal(2, members.Count);
            Assert.Equal(1, members.Count(m => m.GetProperty("isOwner").GetBoolean()));
            Assert.Equal(who.Email, members.Single(m => m.GetProperty("isMe").GetBoolean()).GetProperty("email").GetString());
        }
    }

    [Fact]
    public async Task Guardian_HasSamePowerAsOwner_ExceptInviteRemoveAndDeleteFamily()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var dad = await Dad(mom);
        await Expect(HttpStatusCode.OK, dad.Send(HttpMethod.Patch, kid.Url(), new { name = "Do bo doi" }), "bố đổi tên máy");
        await Expect(HttpStatusCode.OK, dad.Get(kid.Url("/policy")));
        await Expect(HttpStatusCode.OK, dad.Post(kid.Url("/commands"), new { type = "pause", payloadJson = """{"minutes":5}""" }));
        // Bố không mời, không xóa gia đình.
        await Expect(HttpStatusCode.Forbidden, dad.Post("/api/family/invite"), "bố mời");
        await Expect(HttpStatusCode.Forbidden, dad.Send(HttpMethod.Delete, "/api/auth/account", new { password = "password123", confirm = true }), "bố xóa gia đình");
        await Expect(HttpStatusCode.OK, mom.Get(kid.Url("/policy")), "gia đình còn nguyên");
        // Bố hủy ghép máy con (quyền ngang mẹ): mẹ cũng không thấy nữa.
        await Expect(HttpStatusCode.NoContent, dad.Delete(kid.Url()), "bố hủy ghép");
        Assert.Empty(await DeviceIds(mom));
    }

    [Fact]
    public async Task InviteCode_IsOneTime_AndShapeChecked()
    {
        var mom = await Api.NewMother();
        var code = await Invite(mom);
        var body = new { code, email = Api.UniqueEmail(), password = "password123" };
        await Expect(HttpStatusCode.OK, Api.Post("/api/family/join", null, body));
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/family/join", null, new { code, email = Api.UniqueEmail(), password = "password123" }), "dùng lại mã");
    }

    [Theory]
    [InlineData("""{"code":"1234567","email":"a@b.com","password":"password123"}""")]   // thiếu số
    [InlineData("""{"code":"123456789","email":"a@b.com","password":"password123"}""")] // thừa số
    [InlineData("""{"code":"abcdefgh","email":"a@b.com","password":"password123"}""")]  // không phải số
    [InlineData("""{"code":12345678,"email":"a@b.com","password":"password123"}""")]    // sai kiểu
    [InlineData("""{"code":"12345678","email":"khong-phai-email","password":"password123"}""")]
    [InlineData("""{"code":"12345678","email":"a@b.com","password":"short"}""")]
    [InlineData("""{"code":"12345678","email":"a@b.com"}""")]
    [InlineData("""{}""")]
    public async Task Join_BadShape_Is400(string body) =>
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/family/join", null, body));

    [Fact]
    public async Task Join_UnknownOrExpiredCode_Is400()
    {
        var mom = await Api.NewMother();
        var code = await Invite(mom);
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/family/join", null,
            new { code = code == "00000000" ? "00000001" : "00000000", email = Api.UniqueEmail(), password = "password123" }), "mã lạ");
        await Factory.WithDb(async db =>
        {
            var i = db.FamilyInvites.Single(x => x.Code == code);
            i.ExpiresAt = DateTime.UtcNow.AddMinutes(-1);
            await db.SaveChangesAsync();
        });
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/family/join", null, new { code, email = Api.UniqueEmail(), password = "password123" }), "mã hết hạn");
    }

    [Fact]
    public async Task Invite_ExpiresAfter30Minutes()
    {
        var mom = await Api.NewMother();
        var before = DateTime.UtcNow;
        var j = await Api.Json(await mom.Post("/api/family/invite"));
        var life = j.GetProperty("expiresAt").GetDateTime() - before;
        Assert.InRange(life.TotalMinutes, 29, 31);
    }

    [Fact]
    public async Task NewInvite_CancelsTheOldOne()
    {
        var mom = await Api.NewMother();
        var old = await Invite(mom);
        var fresh = await Invite(mom);
        if (old == fresh) return; // trùng ngẫu nhiên (1/10^8): không còn gì để so
        await Expect(HttpStatusCode.BadRequest, Api.Post("/api/family/join", null, new { code = old, email = Api.UniqueEmail(), password = "password123" }));
        await Expect(HttpStatusCode.OK, Api.Post("/api/family/join", null, new { code = fresh, email = Api.UniqueEmail(), password = "password123" }));
    }

    [Fact]
    public async Task Join_ExistingEmail_Is409_AndCodeStaysUsable()
    {
        var mom = await Api.NewMother();
        var other = await Api.NewMother();
        var code = await Invite(mom);
        await Expect(HttpStatusCode.Conflict, Api.Post("/api/family/join", null, new { code, email = other.Email, password = "password123" }));
        await Expect(HttpStatusCode.OK, Api.Post("/api/family/join", null, new { code, email = Api.UniqueEmail(), password = "password123" }), "mã chưa bị đốt");
    }

    [Fact]
    public async Task Family_IsLimitedToTwoGuardians()
    {
        var mom = await Api.NewMother();
        var dad = await Dad(mom);
        await Expect(HttpStatusCode.Conflict, mom.Post("/api/family/invite"), "mời người thứ 3");
        // Mã tạo trước khi đủ người cũng không vào thêm được: dựng mã trực tiếp trong DB.
        await Factory.WithDb(async db =>
        {
            db.FamilyInvites.Add(new Data.FamilyInvite { FamilyId = mom.FamilyId, Code = "99999999", ExpiresAt = DateTime.UtcNow.AddMinutes(5) });
            await db.SaveChangesAsync();
        });
        await Expect(HttpStatusCode.Conflict, Api.Post("/api/family/join", null, new { code = "99999999", email = Api.UniqueEmail(), password = "password123" }));
        // Chủ xóa bố thì mời lại được.
        var dadId = (await Api.Json(await mom.Get("/api/family"))).GetProperty("members").EnumerateArray()
            .Single(m => !m.GetProperty("isOwner").GetBoolean()).GetProperty("id").GetInt32();
        await Expect(HttpStatusCode.NoContent, mom.Delete($"/api/family/members/{dadId}"));
        await Expect(HttpStatusCode.OK, mom.Post("/api/family/invite"));
    }

    [Fact]
    public async Task Owner_RemovesGuardian_RefreshTokenDies_AndFamilyDataStays()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        var dad = await Dad(mom);
        var dadId = (await Api.Json(await mom.Get("/api/family"))).GetProperty("members").EnumerateArray()
            .Single(m => m.GetProperty("email").GetString() == dad.Email).GetProperty("id").GetInt32();
        await Expect(HttpStatusCode.NoContent, mom.Delete($"/api/family/members/{dadId}"));
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/auth/refresh", null, new { refreshToken = dad.Refresh }), "refresh của bố");
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/auth/login", null, new { email = dad.Email, password = "password123" }), "đăng nhập lại");
        Assert.Equal(new[] { kid.Id }, await DeviceIds(mom));
        await Expect(HttpStatusCode.NotFound, mom.Delete($"/api/family/members/{dadId}"), "xóa lần hai");
    }

    [Fact]
    public async Task RemoveMember_Rules()
    {
        var mom = await Api.NewMother();
        var dad = await Dad(mom);
        var members = (await Api.Json(await mom.Get("/api/family"))).GetProperty("members").EnumerateArray().ToList();
        var momId = members.Single(m => m.GetProperty("isOwner").GetBoolean()).GetProperty("id").GetInt32();
        var dadId = members.Single(m => !m.GetProperty("isOwner").GetBoolean()).GetProperty("id").GetInt32();
        await Expect(HttpStatusCode.BadRequest, mom.Delete($"/api/family/members/{momId}"), "chủ tự xóa mình");
        await Expect(HttpStatusCode.Forbidden, dad.Delete($"/api/family/members/{momId}"), "bố xóa chủ");
        await Expect(HttpStatusCode.Forbidden, dad.Delete($"/api/family/members/{dadId}"), "bố tự xóa qua members");
        // Gia đình khác: 404, không lộ người đó có tồn tại.
        var stranger = await Api.NewMother();
        var strangerId = (await Api.Json(await stranger.Get("/api/family"))).GetProperty("members")[0].GetProperty("id").GetInt32();
        await Expect(HttpStatusCode.NotFound, mom.Delete($"/api/family/members/{strangerId}"), "xóa người nhà khác");
        await Expect(HttpStatusCode.OK, stranger.Get("/api/family"), "người lạ còn nguyên");
        await Expect(HttpStatusCode.NotFound, mom.Delete("/api/family/members/99999999"), "id không có");
    }

    [Fact]
    public async Task Guardian_CanLeave_OwnerCannot()
    {
        var mom = await Api.NewMother();
        var dad = await Dad(mom);
        await Expect(HttpStatusCode.Forbidden, mom.Post("/api/family/leave"), "chủ rời");
        await Expect(HttpStatusCode.NoContent, dad.Post("/api/family/leave"), "bố rời");
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/auth/refresh", null, new { refreshToken = dad.Refresh }));
        Assert.Single((await Api.Json(await mom.Get("/api/family"))).GetProperty("members").EnumerateArray());
    }

    [Fact]
    public async Task OwnerDeletesFamily_RemovesGuardianAndInvites()
    {
        var mom = await Api.NewMother();
        var dad = await Dad(mom);
        await Expect(HttpStatusCode.NoContent, mom.Send(HttpMethod.Delete, "/api/auth/account", new { password = "password123", confirm = true }));
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/auth/refresh", null, new { refreshToken = dad.Refresh }));
        await Factory.WithDb(async db =>
        {
            Assert.False(db.Parents.Any(p => p.FamilyId == mom.FamilyId));
            Assert.False(db.FamilyInvites.Any(i => i.FamilyId == mom.FamilyId));
            await Task.CompletedTask;
        });
    }

    [Fact]
    public async Task ExistingParents_DefaultToOwner_AndRegisterMakesOwner()
    {
        var mom = await Api.NewMother();
        Assert.True((await Api.Json(await mom.Get("/api/family"))).GetProperty("isOwner").GetBoolean());
    }

    [Fact]
    public async Task Family_Endpoints_RequireParentRole()
    {
        var mom = await Api.NewMother();
        var kid = await mom.PairKid();
        await Expect(HttpStatusCode.Unauthorized, Api.Get("/api/family"));
        await Expect(HttpStatusCode.Unauthorized, Api.Post("/api/family/invite", null));
        await Expect(HttpStatusCode.Forbidden, kid.Get("/api/family"), "máy con xem gia đình");
        await Expect(HttpStatusCode.Forbidden, kid.Post("/api/family/invite"), "máy con mời");
        await Expect(HttpStatusCode.Forbidden, kid.Post("/api/family/leave"));
    }

    [Fact]
    public async Task Swagger_ListsFamilyEndpoints()
    {
        var paths = (await Api.Json(await Api.Get("/swagger/v1/swagger.json"))).GetProperty("paths");
        foreach (var p in new[] { "/api/family", "/api/family/invite", "/api/family/join", "/api/family/leave", "/api/family/members/{parentId}" })
            Assert.True(paths.TryGetProperty(p, out _), $"Swagger thiếu {p}");
    }
}
