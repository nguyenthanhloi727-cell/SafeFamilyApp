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
public class AuthController(AppDb db, TokenService tokens) : ControllerBase
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
        var parent = new Parent { Family = family, Email = email, PasswordHash = PasswordHasher.Hash(req.Password) };
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
