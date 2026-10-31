using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Dtos;
using SafeFamily.Api.Services;

namespace SafeFamily.Api.Controllers;

/// <summary>Mẹ đánh dấu cảnh báo của máy con đã đọc (API-10).</summary>
[ApiController]
[Route("api/alerts")]
[Authorize(Roles = Roles.Parent)]
public class AlertsController(AppDb db) : ApiBase
{
    /// <summary>
    /// Đánh dấu đã đọc (gọi lại nhiều lần vẫn giữ giờ đọc đầu tiên). Chỉ đổi cờ đọc, không đổi luật hay lệnh nào.
    /// Cảnh báo của máy gia đình khác hoặc máy đã hủy ghép → 404.
    /// </summary>
    [HttpPost("{id:int}/read")]
    public async Task<ActionResult<AlertDto>> MarkRead(int id)
    {
        var row = await db.Alerts.FirstOrDefaultAsync(a => a.Id == id &&
            db.Devices.Any(d => d.Id == a.DeviceId && d.FamilyId == FamilyId && !d.Revoked));
        if (row is null) return NotFound();
        if (row.ReadAt is null)
        {
            row.ReadAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }
        return AlertRules.ToDto(row);
    }
}
