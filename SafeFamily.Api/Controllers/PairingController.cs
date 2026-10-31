using System.Security.Cryptography;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Dtos;
using SafeFamily.Api.Services;

namespace SafeFamily.Api.Controllers;

[ApiController]
[Route("api/pairing")]
public class PairingController(AppDb db, TokenService tokens) : ApiBase
{
    static readonly TimeSpan CodeLife = TimeSpan.FromMinutes(10);

    /// <summary>Mẹ tạo mã 6 số, hết hạn sau 10 phút, dùng một lần.</summary>
    [HttpPost("code")]
    [Authorize(Roles = Roles.Parent)]
    public async Task<ActionResult<CodeResponse>> CreateCode(CreateCodeRequest req)
    {
        // Dọn mã hết hạn / đã dùng của gia đình này.
        var old = db.Pairings.Where(p => p.FamilyId == FamilyId && (p.UsedAt != null || p.ExpiresAt < DateTime.UtcNow));
        db.Pairings.RemoveRange(old);

        string code;
        do { code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6"); }
        while (await db.Pairings.AnyAsync(p => p.Code == code && p.UsedAt == null && p.ExpiresAt > DateTime.UtcNow));

        var pairing = new Pairing
        {
            FamilyId = FamilyId,
            Code = code,
            DeviceName = string.IsNullOrWhiteSpace(req.DeviceName) ? "Máy của con" : req.DeviceName.Trim(),
            ExpiresAt = DateTime.UtcNow.Add(CodeLife),
        };
        db.Pairings.Add(pairing);
        await db.SaveChangesAsync();
        return new CodeResponse(code, pairing.ExpiresAt);
    }

    /// <summary>Con nhập mã để nhận token thiết bị. Giới hạn tần suất theo IP (chính sách "claim").</summary>
    [HttpPost("claim")]
    [AllowAnonymous]
    [EnableRateLimiting("claim")]
    public async Task<ActionResult<ClaimResponse>> Claim(ClaimRequest req)
    {
        var pairing = await db.Pairings.FirstOrDefaultAsync(p =>
            p.Code == req.Code && p.UsedAt == null && p.ExpiresAt > DateTime.UtcNow);
        if (pairing is null) return BadRequest(new { error = "Mã sai hoặc đã hết hạn." });

        pairing.UsedAt = DateTime.UtcNow;
        var device = new Device { FamilyId = pairing.FamilyId, Name = pairing.DeviceName, LastSeenAt = DateTime.UtcNow };
        db.Devices.Add(device);
        await db.SaveChangesAsync();
        return new ClaimResponse(tokens.DeviceToken(device.Id, device.FamilyId), device.Id, device.Name);
    }
}
