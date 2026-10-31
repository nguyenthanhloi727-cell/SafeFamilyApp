using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Dtos;
using SafeFamily.Api.Services;

namespace SafeFamily.Api.Controllers;

/// <summary>
/// Người giám hộ thứ 2 (API-02). Cả hai cùng FamilyId nên thấy cùng danh sách máy con và có quyền ngang nhau,
/// trừ: chỉ chủ (<see cref="Parent.IsOwner"/>) mời/xóa người giám hộ và xóa tài khoản gia đình.
/// </summary>
[ApiController]
[Route("api/family")]
public class FamilyController(AppDb db, TokenService tokens) : ApiBase
{
    static readonly TimeSpan RefreshLife = TimeSpan.FromDays(60);

    /// <summary>Tên gia đình và danh sách người giám hộ (email, ai là chủ, đâu là mình).</summary>
    [HttpGet]
    [Authorize(Roles = Roles.Parent)]
    public async Task<ActionResult<FamilyDto>> Get()
    {
        var me = await db.Parents.FindAsync(SubjectId);
        if (me is null || me.FamilyId != FamilyId) return NotFound();
        var family = await db.Families.FindAsync(FamilyId);
        var members = await db.Parents.Where(p => p.FamilyId == FamilyId).OrderBy(p => p.Id)
            .Select(p => new FamilyMemberDto(p.Id, p.Email, p.IsOwner, p.Id == me.Id, p.CreatedAt)).ToListAsync();
        return new FamilyDto(FamilyId, family?.Name ?? "", me.IsOwner, members);
    }

    /// <summary>
    /// Chủ tạo mã mời 8 số, hạn 30 phút, dùng một lần (mỗi gia đình một mã còn hiệu lực, tạo mới thì mã cũ bị hủy).
    /// Không phải chủ → 403. Gia đình đã đủ <see cref="FamilyRules.MaxGuardians"/> người → 409.
    /// </summary>
    [HttpPost("invite")]
    [Authorize(Roles = Roles.Parent)]
    public async Task<ActionResult<CodeResponse>> Invite()
    {
        var me = await db.Parents.FindAsync(SubjectId);
        if (me is null || me.FamilyId != FamilyId) return NotFound();
        if (!me.IsOwner) return Forbidden("Chỉ chủ gia đình mới mời được người giám hộ.");
        if (await db.Parents.CountAsync(p => p.FamilyId == FamilyId) >= FamilyRules.MaxGuardians)
            return Conflict(new { error = $"Gia đình đã đủ {FamilyRules.MaxGuardians} người giám hộ." });

        db.FamilyInvites.RemoveRange(db.FamilyInvites.Where(i => i.FamilyId == FamilyId));
        string code;
        do { code = FamilyRules.NewCode(); }
        while (await db.FamilyInvites.AnyAsync(i => i.Code == code && i.UsedAt == null && i.ExpiresAt > DateTime.UtcNow));
        var invite = new FamilyInvite { FamilyId = FamilyId, Code = code, ExpiresAt = DateTime.UtcNow.Add(FamilyRules.InviteLife) };
        db.FamilyInvites.Add(invite);
        await db.SaveChangesAsync();
        return new CodeResponse(code, invite.ExpiresAt);
    }

    /// <summary>
    /// Người được mời đăng ký tài khoản mới bằng mã (không cần đăng nhập) và vào gia đình của chủ mã.
    /// Mã sai / hết hạn / đã dùng → 400 cùng một thông báo; email đã đăng ký → 409; gia đình đã đủ người → 409.
    /// Dò mã bị giới hạn theo IP bằng chính sách "claim" như mã ghép đôi.
    /// </summary>
    [HttpPost("join")]
    [AllowAnonymous]
    [EnableRateLimiting("claim")]
    public async Task<ActionResult<AuthResponse>> Join(JoinFamilyRequest req)
    {
        var now = DateTime.UtcNow;
        var invite = await db.FamilyInvites.FirstOrDefaultAsync(i => i.Code == req.Code && i.UsedAt == null && i.ExpiresAt > now);
        if (invite is null) return BadRequest(new { error = "Mã mời sai hoặc đã hết hạn." });
        var email = req.Email.Trim().ToLowerInvariant();
        if (await db.Parents.AnyAsync(p => p.Email == email))
            return Conflict(new { error = "Email đã được đăng ký." });
        if (await db.Parents.CountAsync(p => p.FamilyId == invite.FamilyId) >= FamilyRules.MaxGuardians)
            return Conflict(new { error = $"Gia đình đã đủ {FamilyRules.MaxGuardians} người giám hộ." });

        invite.UsedAt = now;
        var parent = new Parent { FamilyId = invite.FamilyId, Email = email, PasswordHash = PasswordHasher.Hash(req.Password) };
        db.Parents.Add(parent);
        await db.SaveChangesAsync();
        var refresh = TokenService.NewRefreshToken();
        db.RefreshTokens.Add(new RefreshToken { ParentId = parent.Id, TokenHash = TokenService.Hash(refresh), ExpiresAt = now.Add(RefreshLife) });
        await db.SaveChangesAsync();
        return new AuthResponse(tokens.ParentAccessToken(parent.Id, parent.FamilyId), refresh, parent.FamilyId);
    }

    /// <summary>
    /// Chủ xóa người giám hộ khác (mọi refresh token của họ bị xóa; access token đã cấp còn dùng tối đa 30 phút).
    /// Không phải chủ → 403; tự xóa mình → 400; người ở gia đình khác hoặc không có → 404.
    /// </summary>
    [HttpDelete("members/{parentId:int}")]
    [Authorize(Roles = Roles.Parent)]
    public async Task<IActionResult> RemoveMember(int parentId)
    {
        var me = await db.Parents.FindAsync(SubjectId);
        if (me is null || me.FamilyId != FamilyId) return NotFound();
        var target = await db.Parents.FirstOrDefaultAsync(p => p.Id == parentId && p.FamilyId == FamilyId);
        if (target is null) return NotFound();
        if (!me.IsOwner) return Forbidden("Chỉ chủ gia đình mới xóa được người giám hộ.");
        if (target.Id == me.Id) return BadRequest(new { error = "Chủ gia đình không tự xóa mình; muốn xóa cả gia đình hãy dùng xóa tài khoản." });
        await Remove(target.Id);
        return NoContent();
    }

    /// <summary>Người giám hộ thứ 2 tự rời gia đình (xóa tài khoản của mình). Chủ gia đình → 403 (dùng xóa tài khoản gia đình).</summary>
    [HttpPost("leave")]
    [Authorize(Roles = Roles.Parent)]
    public async Task<IActionResult> Leave()
    {
        var me = await db.Parents.FindAsync(SubjectId);
        if (me is null || me.FamilyId != FamilyId) return NotFound();
        if (me.IsOwner) return Forbidden("Chủ gia đình không rời được; muốn xóa cả gia đình hãy dùng xóa tài khoản.");
        await Remove(me.Id);
        return NoContent();
    }

    async Task Remove(int parentId)
    {
        await using var tx = await db.Database.BeginTransactionAsync();
        await db.RefreshTokens.Where(t => t.ParentId == parentId).ExecuteDeleteAsync();
        await db.PasswordResets.Where(r => r.ParentId == parentId).ExecuteDeleteAsync();
        await db.Parents.Where(p => p.Id == parentId).ExecuteDeleteAsync();
        await tx.CommitAsync();
    }

    ObjectResult Forbidden(string error) => StatusCode(StatusCodes.Status403Forbidden, new { error });
}
