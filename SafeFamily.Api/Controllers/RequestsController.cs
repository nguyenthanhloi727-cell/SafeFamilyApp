using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Dtos;
using SafeFamily.Api.Services;

namespace SafeFamily.Api.Controllers;

/// <summary>Mẹ quyết định yêu cầu của máy con (API-06).</summary>
[ApiController]
[Route("api/requests")]
[Authorize(Roles = Roles.Parent)]
public class RequestsController(AppDb db) : ApiBase
{
    /// <summary>
    /// Duyệt hoặc từ chối. Server tạo lệnh tương ứng (<c>study_approve/study_reject</c> hoặc <c>extra_time_grant</c>)
    /// cùng một lần lưu với việc đổi trạng thái, nên không có chuyện đã duyệt mà thiếu lệnh. Đã quyết định rồi,
    /// hoặc chờ quá 24 giờ → 409. Yêu cầu của máy gia đình khác hoặc máy đã hủy ghép → 404.
    /// </summary>
    [HttpPut("{id:int}")]
    public async Task<ActionResult<ChildRequestDto>> Decide(int id, DecideRequest req)
    {
        var row = await db.ChildRequests.FirstOrDefaultAsync(r => r.Id == id &&
            db.Devices.Any(d => d.Id == r.DeviceId && d.FamilyId == FamilyId && !d.Revoked));
        if (row is null) return NotFound();

        if (req.Decision is not (RequestRules.Approved or RequestRules.Rejected))
            return BadRequest(new { error = "decision phải là approved hoặc rejected." });
        var approved = req.Decision == RequestRules.Approved;

        var minutes = 0;
        if (row.Kind == RequestRules.ExtraTime && approved)
        {
            minutes = req.Minutes ?? RequestRules.RequestedMinutes(row.Payload);
            if (minutes is < 1 or > CommandRules.MaxExtraMinutes)
                return BadRequest(new { error = $"minutes phải từ 1 đến {CommandRules.MaxExtraMinutes}." });
        }
        else if (req.Minutes is not null)
            return BadRequest(new { error = "minutes chỉ dùng khi duyệt extra_time." });

        if (row.Status != RequestRules.Pending) return Conflict(new { error = "Yêu cầu đã được quyết định.", status = row.Status });
        if (row.CreatedAt <= DateTime.UtcNow - RequestRules.PendingMaxAge)
            return Conflict(new { error = "Yêu cầu đã hết hạn (quá 24 giờ).", status = row.Status });

        row.Status = req.Decision;
        row.DecidedAt = DateTime.UtcNow;
        if (RequestRules.CommandFor(row.Kind, approved, minutes) is var (type, payload))
        {
            var error = CommandRules.Validate(type, payload);
            if (error is not null) return StatusCode(500, new { error });
            db.Commands.Add(new Command { DeviceId = row.DeviceId, Type = type, PayloadJson = payload });
        }
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateConcurrencyException) { return Conflict(new { error = "Yêu cầu vừa được quyết định ở nơi khác." }); }
        return DeviceSelfController.RequestDto(row);
    }
}
