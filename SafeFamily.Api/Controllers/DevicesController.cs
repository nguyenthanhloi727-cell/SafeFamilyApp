using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Dtos;
using SafeFamily.Api.Services;

namespace SafeFamily.Api.Controllers;

/// <summary>Phía mẹ: quản lý máy con của gia đình mình.</summary>
[ApiController]
[Route("api/devices")]
[Authorize(Roles = Roles.Parent)]
public class DevicesController(AppDb db) : ApiBase
{
    const int MaxPolicyBytes = 64 * 1024;

    [HttpGet]
    public async Task<List<DeviceDto>> List() =>
        await db.Devices.Where(d => d.FamilyId == FamilyId && !d.Revoked)
            .Select(d => new DeviceDto(d.Id, d.Name, d.PairedAt, d.LastSeenAt)).ToListAsync();

    /// <summary>Hủy ghép: token của máy con hết tác dụng ngay.</summary>
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Unpair(int id)
    {
        var device = await Own(id);
        if (device is null) return NotFound();
        device.Revoked = true;
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("{id:int}/policy")]
    public async Task<ActionResult<PolicyDto>> GetPolicy(int id)
    {
        if (await Own(id) is null) return NotFound();
        return ToDto(await db.Policies.FirstOrDefaultAsync(p => p.DeviceId == id));
    }

    /// <summary>Ghi luật. Phiên bản mẹ gửi (ExpectedVersion) phải bằng phiên bản hiện tại, lệch thì 409.</summary>
    [HttpPut("{id:int}/policy")]
    public async Task<ActionResult<PolicyDto>> PutPolicy(int id, PutPolicyRequest req)
    {
        if (await Own(id) is null) return NotFound();
        // Server không hiểu nội dung (schema ở lib/core/network/policy_schema.dart): chỉ
        // kiểm tra kích thước (byte, không phải ký tự) và là một đối tượng JSON hợp lệ.
        if (System.Text.Encoding.UTF8.GetByteCount(req.Json) > MaxPolicyBytes)
            return BadRequest(new { error = "Luật quá lớn." });
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(req.Json);
            if (doc.RootElement.ValueKind != System.Text.Json.JsonValueKind.Object)
                return BadRequest(new { error = "Luật phải là một đối tượng JSON." });
        }
        catch (System.Text.Json.JsonException) { return BadRequest(new { error = "Json không hợp lệ." }); }

        var policy = await db.Policies.FirstOrDefaultAsync(p => p.DeviceId == id);
        var current = policy?.Version ?? 0;
        if (req.ExpectedVersion != current)
            return Conflict(new { error = "Luật đã đổi ở nơi khác.", currentVersion = current });

        if (policy is null) db.Policies.Add(policy = new Policy { DeviceId = id });
        policy.Json = req.Json;
        policy.Version = current + 1;
        policy.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return ToDto(policy);
    }

    [HttpGet("{id:int}/apps")]
    public async Task<ActionResult<List<InstalledAppDto>>> Apps(int id)
    {
        if (await Own(id) is null) return NotFound();
        return await db.InstalledApps.Where(a => a.DeviceId == id).OrderBy(a => a.Label)
            .Select(a => new InstalledAppDto(a.PackageName, a.Label, a.FirstSeenAt)).ToListAsync();
    }

    /// <summary>Tạo lệnh tức thời, ví dụ Type = "pause". Máy con nhận khi polling kế tiếp.</summary>
    [HttpPost("{id:int}/commands")]
    public async Task<ActionResult<CommandDto>> CreateCommand(int id, CreateCommandRequest req)
    {
        if (await Own(id) is null) return NotFound();
        var payload = req.PayloadJson ?? "{}";
        var error = CommandRules.Validate(req.Type, payload);
        if (error is not null) return BadRequest(new { error });
        var cmd = new Command { DeviceId = id, Type = req.Type, PayloadJson = payload };
        db.Commands.Add(cmd);
        await db.SaveChangesAsync();
        return ToDto(cmd);
    }

    [HttpGet("{id:int}/commands")]
    public async Task<ActionResult<List<CommandDto>>> Commands(int id)
    {
        if (await Own(id) is null) return NotFound();
        return await db.Commands.Where(c => c.DeviceId == id).OrderByDescending(c => c.Id).Take(50)
            .Select(c => new CommandDto(c.Id, c.Type, c.PayloadJson, c.CreatedAt, c.DoneAt)).ToListAsync();
    }

    /// <summary>Vị trí mới nhất của máy con (204 nếu chưa có).</summary>
    [HttpGet("{id:int}/location")]
    public async Task<ActionResult<LocationDto>> LastLocation(int id)
    {
        if (await Own(id) is null) return NotFound();
        var last = await db.LocationPoints.Where(l => l.DeviceId == id).OrderByDescending(l => l.Time)
            .Select(l => new LocationDto(l.Lat, l.Lng, l.Accuracy, l.Time)).FirstOrDefaultAsync();
        return last is null ? NoContent() : last;
    }

    [HttpGet("{id:int}/locations")]
    public async Task<ActionResult<List<LocationDto>>> LocationHistory(int id)
    {
        if (await Own(id) is null) return NotFound();
        return await db.LocationPoints.Where(l => l.DeviceId == id).OrderByDescending(l => l.Time).Take(200)
            .Select(l => new LocationDto(l.Lat, l.Lng, l.Accuracy, l.Time)).ToListAsync();
    }

    [HttpGet("{id:int}/geofences")]
    public async Task<ActionResult<GeofencesDto>> GetGeofences(int id)
    {
        var device = await Own(id);
        if (device is null) return NotFound();
        return await GeofencesOf(db, device);
    }

    /// <summary>Thay toàn bộ bộ hàng rào. Lệch ExpectedVersion thì 409. Tối đa 100 vùng (giới hạn của GeofencingClient).</summary>
    [HttpPut("{id:int}/geofences")]
    public async Task<ActionResult<GeofencesDto>> PutGeofences(int id, PutGeofencesRequest req)
    {
        var device = await Own(id);
        if (device is null) return NotFound();
        if (req.Geofences.Count > 100) return BadRequest(new { error = "Tối đa 100 hàng rào." });
        if (req.ExpectedVersion != device.GeofenceVersion)
            return Conflict(new { error = "Hàng rào đã đổi ở nơi khác.", currentVersion = device.GeofenceVersion });

        var old = await db.Geofences.Where(g => g.DeviceId == id).ToListAsync();
        var byId = old.ToDictionary(g => g.Id);
        var keep = new HashSet<int>();
        foreach (var item in req.Geofences)
        {
            if (item.Id != 0 && byId.TryGetValue(item.Id, out var row)) { keep.Add(row.Id); Apply(row, item); }
            else db.Geofences.Add(Apply(new Geofence { DeviceId = id }, item));
        }
        db.Geofences.RemoveRange(old.Where(g => !keep.Contains(g.Id)));
        device.GeofenceVersion++;
        await db.SaveChangesAsync();
        return await GeofencesOf(db, device);
    }

    [HttpGet("{id:int}/geofence-events")]
    public async Task<ActionResult<List<GeofenceEventDto>>> GeofenceEvents(int id, [FromQuery] long afterId = 0)
    {
        if (await Own(id) is null) return NotFound();
        var q = db.GeofenceEvents.Where(e => e.DeviceId == id && e.Id > afterId);
        // Không có mốc: lấy 100 sự kiện MỚI nhất. Có mốc: 100 sự kiện kế tiếp để không sót khi dò theo con trỏ.
        var rows = afterId == 0
            ? (await q.OrderByDescending(e => e.Id).Take(100).ToListAsync()).AsEnumerable().Reverse().ToList()
            : await q.OrderBy(e => e.Id).Take(100).ToListAsync();
        return rows.Select(e => new GeofenceEventDto(e.Id, e.GeofenceId, e.GeofenceName, e.Type, e.Time)).ToList();
    }

    internal static async Task<GeofencesDto> GeofencesOf(AppDb db, Device d) =>
        new(d.GeofenceVersion, await db.Geofences.Where(g => g.DeviceId == d.Id).OrderBy(g => g.Id)
            .Select(g => new GeofenceItem(g.Id, g.Name, g.Lat, g.Lng, g.RadiusM)).ToListAsync());

    static Geofence Apply(Geofence g, GeofenceItem i)
    {
        g.Name = i.Name; g.Lat = i.Lat; g.Lng = i.Lng; g.RadiusM = i.RadiusM;
        return g;
    }

    Task<Device?> Own(int id) =>
        db.Devices.FirstOrDefaultAsync(d => d.Id == id && d.FamilyId == FamilyId && !d.Revoked);

    static PolicyDto ToDto(Policy? p) => p is null ? new PolicyDto(0, "{}", DateTime.MinValue) : new(p.Version, p.Json, p.UpdatedAt);
    static CommandDto ToDto(Command c) => new(c.Id, c.Type, c.PayloadJson, c.CreatedAt, c.DoneAt);
}

/// <summary>Phía con: máy con hỏi luật/lệnh (polling) và gửi danh sách app. Mỗi lần gọi cập nhật LastSeenAt.</summary>
[ApiController]
[Route("api/devices/me")]
[Authorize(Roles = Roles.Device)]
public class DeviceSelfController(AppDb db) : ApiBase
{
    static readonly TimeSpan LocationRetention = TimeSpan.FromDays(7);

    [HttpGet("policy")]
    public async Task<ActionResult<PolicyDto>> Policy()
    {
        if (!await Touch()) return Unauthorized();
        var p = await db.Policies.FirstOrDefaultAsync(p => p.DeviceId == SubjectId);
        return p is null ? new PolicyDto(0, "{}", DateTime.MinValue) : new PolicyDto(p.Version, p.Json, p.UpdatedAt);
    }

    [HttpGet("commands")]
    public async Task<ActionResult<List<CommandDto>>> Pending()
    {
        if (!await Touch()) return Unauthorized();
        // Lệnh quá hạn không giao nữa (lỗi #5): máy con offline lâu không được áp lệnh cũ.
        var oldest = DateTime.UtcNow - CommandRules.MaxAge;
        return await db.Commands.Where(c => c.DeviceId == SubjectId && c.DoneAt == null && c.CreatedAt > oldest).OrderBy(c => c.Id)
            .Select(c => new CommandDto(c.Id, c.Type, c.PayloadJson, c.CreatedAt, c.DoneAt)).ToListAsync();
    }

    /// <summary>Máy con xác nhận đã thực hiện lệnh.</summary>
    [HttpPost("commands/{id:int}/ack")]
    public async Task<IActionResult> Ack(int id)
    {
        if (!await Touch()) return Unauthorized();
        var cmd = await db.Commands.FirstOrDefaultAsync(c => c.Id == id && c.DeviceId == SubjectId);
        if (cmd is null) return NotFound();
        cmd.DoneAt ??= DateTime.UtcNow;
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>Gửi danh sách app đã cài (tên + tên gói). Thêm app mới, cập nhật nhãn, giữ FirstSeenAt.</summary>
    [HttpPost("apps")]
    public async Task<IActionResult> PostApps(PostAppsRequest req)
    {
        if (!await Touch()) return Unauthorized();
        if (req.Apps.Count > 2000) return BadRequest(new { error = "Quá nhiều app." });
        var existing = await db.InstalledApps.Where(a => a.DeviceId == SubjectId).ToDictionaryAsync(a => a.PackageName);
        foreach (var item in req.Apps.DistinctBy(a => a.PackageName))
        {
            if (existing.TryGetValue(item.PackageName, out var row)) row.Label = item.Label;
            else db.InstalledApps.Add(new InstalledApp { DeviceId = SubjectId, PackageName = item.PackageName, Label = item.Label });
        }
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>Gửi lô vị trí. Bỏ điểm có thời gian ở tương lai quá 5 phút; xóa điểm cũ hơn LocationRetention.</summary>
    [HttpPost("locations")]
    public async Task<IActionResult> PostLocations(PostLocationsRequest req)
    {
        if (!await Touch()) return Unauthorized();
        if (req.Points.Count > 500) return BadRequest(new { error = "Quá nhiều điểm." });
        var now = DateTime.UtcNow;
        foreach (var p in req.Points.Where(p => p.Time.ToUniversalTime() < now.AddMinutes(5)))
            db.LocationPoints.Add(new LocationPoint
            {
                DeviceId = SubjectId, Lat = p.Lat, Lng = p.Lng, Accuracy = p.Accuracy, Time = p.Time.ToUniversalTime(),
            });
        var cutoff = now - LocationRetention;
        await db.LocationPoints.Where(l => l.DeviceId == SubjectId && l.Time < cutoff).ExecuteDeleteAsync();
        await db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("geofences")]
    public async Task<ActionResult<GeofencesDto>> Geofences()
    {
        if (!await Touch()) return Unauthorized();
        var device = await db.Devices.FirstAsync(d => d.Id == SubjectId);
        return await DevicesController.GeofencesOf(db, device);
    }

    /// <summary>Máy con báo vào/ra vùng (xếp hàng khi offline rồi gửi bù). Tên vùng lấy từ server.</summary>
    [HttpPost("geofence-events")]
    public async Task<IActionResult> PostGeofenceEvents(PostGeofenceEventsRequest req)
    {
        if (!await Touch()) return Unauthorized();
        if (req.Events.Count > 200) return BadRequest(new { error = "Quá nhiều sự kiện." });
        var fences = await db.Geofences.Where(g => g.DeviceId == SubjectId).ToDictionaryAsync(g => g.Id);
        foreach (var e in req.Events)
        {
            if (!fences.TryGetValue(e.GeofenceId, out var fence)) continue;
            db.GeofenceEvents.Add(new GeofenceEvent
            {
                DeviceId = SubjectId, GeofenceId = fence.Id, GeofenceName = fence.Name,
                Type = e.Type, Time = e.Time.ToUniversalTime(),
            });
        }
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>Token của máy con bị hủy ghép (Revoked) thì trả false → 401.</summary>
    async Task<bool> Touch()
    {
        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == SubjectId);
        if (device is null || device.Revoked) return false;
        device.LastSeenAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return true;
    }
}
