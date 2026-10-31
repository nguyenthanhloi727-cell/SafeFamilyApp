using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Dtos;
using SafeFamily.Api.Services;

namespace SafeFamily.Api.Controllers;

[ApiController]
[Route("api/auth")]
[EnableRateLimiting("auth")]
public class AuthController(AppDb db, TokenService tokens, JwtOptions jwt, IEmailSender mail) : ApiBase
{
    static readonly TimeSpan RefreshLife = TimeSpan.FromDays(60);

    /// <summary>Mẹ đăng ký: tạo luôn gia đình mới.</summary>
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest req)
    {
        var email = req.Email.Trim().ToLowerInvariant();
        if (await db.Parents.AnyAsync(p => p.Email == email))
            return Conflict(new { error = "Email đã được đăng ký." });

        var family = new Family { Name = string.IsNullOrWhiteSpace(req.FamilyName) ? "Gia đình" : req.FamilyName.Trim() };
        var parent = new Parent { Family = family, Email = email, PasswordHash = PasswordHasher.Hash(req.Password), IsOwner = true };
        db.Parents.Add(parent);
        await db.SaveChangesAsync();
        return await Issue(parent);
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest req)
    {
        var email = req.Email.Trim().ToLowerInvariant();
        var parent = await db.Parents.FirstOrDefaultAsync(p => p.Email == email);
        // Cùng một thông báo cho sai email và sai mật khẩu.
        if (parent is null || !PasswordHasher.Verify(req.Password, parent.PasswordHash))
            return Unauthorized(new { error = "Email hoặc mật khẩu không đúng." });
        return await Issue(parent);
    }

    /// <summary>Đổi refresh token cũ lấy cặp token mới (token cũ bị thu hồi).</summary>
    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> Refresh(RefreshRequest req)
    {
        var hash = TokenService.Hash(req.RefreshToken);
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash);
        if (stored is null || stored.RevokedAt != null || stored.ExpiresAt < DateTime.UtcNow)
            return Unauthorized(new { error = "Phiên đăng nhập hết hạn." });
        var parent = await db.Parents.FindAsync(stored.ParentId);
        if (parent is null) return Unauthorized();
        stored.RevokedAt = DateTime.UtcNow;
        return await Issue(parent);
    }

    /// <summary>
    /// Đăng xuất (API-03): thu hồi refresh token gửi lên. Gọi lại hoặc token lạ vẫn 204 (không cho đoán token).
    /// Access token cũ còn dùng được tối đa 30 phút (JWT không trạng thái); sau đó refresh bị 401.
    /// </summary>
    [HttpPost("logout")]
    public async Task<IActionResult> Logout(LogoutRequest req)
    {
        var hash = TokenService.Hash(req.RefreshToken);
        await db.RefreshTokens.Where(t => t.TokenHash == hash && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, DateTime.UtcNow));
        return NoContent();
    }

    /// <summary>
    /// Quên mật khẩu (API-03): luôn 204 dù email có tồn tại hay không (không cho dò email). Có thì gửi mã 6 số, hạn 30 phút;
    /// xin lại trong 60 giây thì bỏ qua. Thư gửi nền, lỗi SMTP chỉ ghi log.
    /// </summary>
    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword(ForgotPasswordRequest req)
    {
        var email = req.Email.Trim().ToLowerInvariant();
        var parent = await db.Parents.FirstOrDefaultAsync(p => p.Email == email);
        if (parent is null) return NoContent();
        var now = DateTime.UtcNow;
        var recent = now - PasswordResetRules.Cooldown;
        if (await db.PasswordResets.AnyAsync(r => r.ParentId == parent.Id && r.CreatedAt > recent))
            return NoContent();
        await db.PasswordResets.Where(r => r.ParentId == parent.Id && r.UsedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(r => r.UsedAt, now));
        var code = PasswordResetRules.NewCode();
        db.PasswordResets.Add(new PasswordReset
        {
            ParentId = parent.Id,
            CodeHash = PasswordResetRules.Hash(code, parent.Id, jwt.Key),
            ExpiresAt = now.Add(PasswordResetRules.Life),
        });
        await db.SaveChangesAsync();
        var minutes = (int)PasswordResetRules.Life.TotalMinutes;
        _ = mail.SendAsync(parent.Email, "SafeFamily: mã đặt lại mật khẩu",
            $"Mã đặt lại mật khẩu của bạn là {code}. Mã có hiệu lực {minutes} phút và dùng một lần.\n" +
            "Nếu bạn không yêu cầu, hãy bỏ qua thư này.");
        return NoContent();
    }

    /// <summary>
    /// Đặt lại mật khẩu bằng mã trong thư (API-03). Mã sai / hết hạn / đã dùng / email lạ đều trả cùng một 400;
    /// nhập sai 5 lần thì mã bị hủy. Thành công thì mọi refresh token cũ bị thu hồi.
    /// </summary>
    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword(ResetPasswordRequest req)
    {
        var bad = BadRequest(new { error = "Mã không đúng hoặc đã hết hạn." });
        var email = req.Email.Trim().ToLowerInvariant();
        var parent = await db.Parents.FirstOrDefaultAsync(p => p.Email == email);
        if (parent is null) return bad;
        var now = DateTime.UtcNow;
        var reset = await db.PasswordResets.Where(r => r.ParentId == parent.Id && r.UsedAt == null && r.ExpiresAt > now)
            .OrderByDescending(r => r.Id).FirstOrDefaultAsync();
        if (reset is null || reset.Attempts >= PasswordResetRules.MaxAttempts) return bad;
        var given = System.Text.Encoding.ASCII.GetBytes(PasswordResetRules.Hash(req.Code, parent.Id, jwt.Key));
        var stored = System.Text.Encoding.ASCII.GetBytes(reset.CodeHash);
        if (!System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(given, stored))
        {
            reset.Attempts++;
            await db.SaveChangesAsync();
            return bad;
        }
        reset.UsedAt = now;
        parent.PasswordHash = PasswordHasher.Hash(req.NewPassword);
        await db.RefreshTokens.Where(t => t.ParentId == parent.Id && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now));
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// Đổi mật khẩu (API-03): cần mật khẩu cũ (sai → 403). Mật khẩu mới 8–128 ký tự và khác mật khẩu cũ (400).
    /// Mọi refresh token khác bị thu hồi; <c>refreshToken</c> trong body (nếu có) là phiên đang dùng và được giữ lại.
    /// </summary>
    [HttpPost("change-password")]
    [Authorize(Roles = Roles.Parent)]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest req)
    {
        var parent = await db.Parents.FindAsync(SubjectId);
        if (parent is null) return NotFound();
        if (!PasswordHasher.Verify(req.CurrentPassword, parent.PasswordHash))
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Mật khẩu hiện tại không đúng." });
        if (req.NewPassword == req.CurrentPassword)
            return BadRequest(new { error = "Mật khẩu mới phải khác mật khẩu cũ." });
        parent.PasswordHash = PasswordHasher.Hash(req.NewPassword);
        var keep = string.IsNullOrEmpty(req.RefreshToken) ? null : TokenService.Hash(req.RefreshToken);
        var now = DateTime.UtcNow;
        await db.RefreshTokens.Where(t => t.ParentId == parent.Id && t.RevokedAt == null && t.TokenHash != keep)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now));
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// Xóa tài khoản (API-03): nhập lại mật khẩu (sai → 403) và <c>confirm:true</c> (thiếu → 400). Xóa vĩnh viễn toàn bộ
    /// dữ liệu gia đình: máy con, luật, lệnh, vị trí, báo cáo, cảnh báo, token. Không hoàn tác được.
    /// </summary>
    [HttpDelete("account")]
    [Authorize(Roles = Roles.Parent)]
    public async Task<IActionResult> DeleteAccount(DeleteAccountRequest req)
    {
        if (req.Confirm != true) return BadRequest(new { error = "Cần xác nhận xóa tài khoản." });
        var parent = await db.Parents.FindAsync(SubjectId);
        if (parent is null || parent.FamilyId != FamilyId) return NotFound();
        if (!parent.IsOwner) // API-02: người giám hộ thứ 2 không xóa được gia đình; muốn rời dùng POST /api/family/leave
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Chỉ chủ gia đình mới xóa được tài khoản gia đình." });
        if (!PasswordHasher.Verify(req.Password, parent.PasswordHash))
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Mật khẩu không đúng." });

        var fam = parent.FamilyId;
        await using var tx = await db.Database.BeginTransactionAsync();
        var devices = db.Devices.Where(d => d.FamilyId == fam).Select(d => d.Id);
        // Bảng chưa khai báo khóa ngoại nên xóa tay từng bảng con; UsageApp xóa theo UsageDay (cascade).
        await db.UsageDays.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.Policies.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.Commands.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.InstalledApps.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.LocationPoints.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.Geofences.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.GeofenceEvents.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.DeviceStatuses.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.ChildRequests.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.Alerts.Where(x => devices.Contains(x.DeviceId)).ExecuteDeleteAsync();
        await db.Devices.Where(x => x.FamilyId == fam).ExecuteDeleteAsync();
        await db.Pairings.Where(x => x.FamilyId == fam).ExecuteDeleteAsync();
        await db.FamilyInvites.Where(x => x.FamilyId == fam).ExecuteDeleteAsync();
        var parents = db.Parents.Where(p => p.FamilyId == fam).Select(p => p.Id);
        await db.RefreshTokens.Where(t => parents.Contains(t.ParentId)).ExecuteDeleteAsync();
        await db.PasswordResets.Where(r => parents.Contains(r.ParentId)).ExecuteDeleteAsync();
        await db.Parents.Where(p => p.FamilyId == fam).ExecuteDeleteAsync();
        await db.Families.Where(f => f.Id == fam).ExecuteDeleteAsync();
        await tx.CommitAsync();
        return NoContent();
    }

    async Task<ActionResult<AuthResponse>> Issue(Parent parent)
    {
        var refresh = TokenService.NewRefreshToken();
        db.RefreshTokens.Add(new RefreshToken
        {
            ParentId = parent.Id,
            TokenHash = TokenService.Hash(refresh),
            ExpiresAt = DateTime.UtcNow.Add(RefreshLife),
        });
        await db.SaveChangesAsync();
        return new AuthResponse(tokens.ParentAccessToken(parent.Id, parent.FamilyId), refresh, parent.FamilyId);
    }
}
