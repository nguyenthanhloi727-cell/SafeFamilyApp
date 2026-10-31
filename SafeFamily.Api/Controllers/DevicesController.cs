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

    /// <summary>
    /// App của máy con (API-07), app mới nhất trước, tối đa 200. <c>status</c> = new|allowed|blocked, bỏ trống = tất cả;
    /// sai → 400. Gia đình khác hoặc máy đã hủy ghép → 404.
    /// </summary>
    [HttpGet("{id:int}/apps")]
    public async Task<ActionResult<List<InstalledAppDto>>> Apps(int id, [FromQuery] string? status = null)
    {
        if (await Own(id) is null) return NotFound();
        if (status is not null && !AppRules.IsStatus(status)) return BadRequest(new { error = "status không hợp lệ." });
        var q = db.InstalledApps.Where(a => a.DeviceId == id);
        if (status is not null) q = q.Where(a => a.Status == status);
        return await q.OrderByDescending(a => a.FirstSeenAt).ThenByDescending(a => a.Id).Take(AppRules.MaxListRows)
            .Select(a => new InstalledAppDto(a.Id, a.PackageName, a.Label, a.FirstSeenAt, a.Status, a.DecidedAt)).ToListAsync();
    }

    /// <summary>
    /// Mẹ cho phép / chặn một app của máy con: body <c>{"status":"allowed"|"blocked"}</c>. Máy con kéo quyết định này ở lượt
    /// đồng bộ kế (<c>GET devices/me/apps/decisions</c>). Tên gói sai dạng → 400; gia đình khác / máy hủy ghép / app chưa
    /// từng được máy con báo → 404.
    /// </summary>
    [HttpPut("{id:int}/apps/{package}")]
    public async Task<ActionResult<InstalledAppDto>> PutAppStatus(int id, string package, PutAppStatusRequest req)
    {
        if (await Own(id) is null) return NotFound();
        if (!CommandRules.IsPackage(package)) return BadRequest(new { error = "Tên gói không hợp lệ." });
        if (!AppRules.IsDecision(req.Status)) return BadRequest(new { error = "status phải là allowed hoặc blocked." });
        var app = await db.InstalledApps.FirstOrDefaultAsync(a => a.DeviceId == id && a.PackageName == package);
        if (app is null) return NotFound();
        app.Status = req.Status;
        app.DecidedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return new InstalledAppDto(app.Id, app.PackageName, app.Label, app.FirstSeenAt, app.Status, app.DecidedAt);
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

    /// <summary>
    /// Trạng thái máy con do chính nó báo (API-09). Chưa báo lần nào thì các trường là mặc định và
    /// ReportedAt = null. App mở tạm đã quá hạn bị lọc bỏ để mẹ không thấy nút "chặn lại" thừa.
    /// </summary>
    [HttpGet("{id:int}/status")]
    public async Task<ActionResult<DeviceStatusDto>> Status(int id)
    {
        var device = await Own(id);
        if (device is null) return NotFound();
        var s = await db.DeviceStatuses.FirstOrDefaultAsync(x => x.DeviceId == id);
        if (s is null) return new DeviceStatusDto(device.LastSeenAt, null, null, 0, false, false, [], null, []);
        var now = DateTime.UtcNow;
        return new DeviceStatusDto(device.LastSeenAt, s.ReportedAt, s.BatteryPercent, s.PolicyVersion, s.IsPaused,
            s.StudyActive, StatusRules.ParsePermissions(s.PermissionsMissingJson), s.AppVersion,
            StatusRules.ParseTempUnlocked(s.TempUnlockedJson).Where(t => t.Until.ToUniversalTime() > now).ToList());
    }

    /// <summary>
    /// Yêu cầu của máy con (API-06), mới nhất trước, tối đa 50. <c>status</c> bỏ trống = tất cả. Yêu cầu chờ quá
    /// 24 giờ bị ẩn (hết hạn). Gia đình khác hoặc máy đã hủy ghép → 404.
    /// </summary>
    [HttpGet("{id:int}/requests")]
    public async Task<ActionResult<List<ChildRequestDto>>> Requests(int id, [FromQuery] string? status = null)
    {
        if (await Own(id) is null) return NotFound();
        if (status is not null && !RequestRules.IsStatus(status)) return BadRequest(new { error = "status không hợp lệ." });
        var oldestPending = DateTime.UtcNow - RequestRules.PendingMaxAge;
        var q = db.ChildRequests.Where(r => r.DeviceId == id &&
            (r.Status != RequestRules.Pending || r.CreatedAt > oldestPending));
        if (status is not null) q = q.Where(r => r.Status == status);
        return await q.OrderByDescending(r => r.Id).Take(50)
            .Select(r => new ChildRequestDto(r.Id, r.DeviceId, r.Kind, r.Payload, r.Status, r.CreatedAt, r.DecidedAt))
            .ToListAsync();
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

    /// <summary>
    /// Máy con báo trạng thái mỗi lượt đồng bộ (API-09): pin, tạm dừng, giờ học, quyền còn thiếu, phiên bản,
    /// app đang mở tạm. Ghi đè dòng cũ. Không nhận trường nào khác.
    /// </summary>
    [HttpPut("status")]
    public async Task<IActionResult> PutStatus(PutStatusRequest req)
    {
        if (!await Touch()) return Unauthorized();
        var now = DateTime.UtcNow;
        var error = StatusRules.Validate(req, now);
        if (error is not null) return BadRequest(new { error });
        var s = await db.DeviceStatuses.FirstOrDefaultAsync(x => x.DeviceId == SubjectId);
        if (s is null) db.DeviceStatuses.Add(s = new DeviceStatus { DeviceId = SubjectId });
        s.BatteryPercent = req.BatteryPercent;
        s.PolicyVersion = req.PolicyVersion;
        s.IsPaused = req.IsPaused;
        s.StudyActive = req.StudyActive;
        s.PermissionsMissingJson = StatusRules.ToJson((req.PermissionsMissing ?? []).Distinct());
        s.AppVersion = string.IsNullOrEmpty(req.AppVersion) ? null : req.AppVersion;
        s.TempUnlockedJson = StatusRules.ToJson((req.TempUnlocked ?? [])
            .DistinctBy(t => t.Package).Select(t => new TempUnlockItem(t.Package, t.Until.ToUniversalTime())));
        s.ReportedAt = now;
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// Con gửi yêu cầu (API-06): <c>extra_time</c> {"minutes":N} hoặc <c>study_done</c> {}. Đã có yêu cầu cùng loại
    /// đang chờ (chưa quá 24 giờ) → 409 kèm <c>id</c> của nó, để máy con gửi bù không tạo trùng mà vẫn theo dõi được.
    /// </summary>
    [HttpPost("requests")]
    public async Task<ActionResult<ChildRequestDto>> CreateRequest(CreateChildRequest req)
    {
        if (!await Touch()) return Unauthorized();
        var error = RequestRules.Validate(req.Kind, req.PayloadJson, out var payload);
        if (error is not null) return BadRequest(new { error });

        var now = DateTime.UtcNow;
        var oldestPending = now - RequestRules.PendingMaxAge;
        var dup = await db.ChildRequests.Where(r => r.DeviceId == SubjectId && r.Kind == req.Kind &&
            r.Status == RequestRules.Pending && r.CreatedAt > oldestPending).OrderByDescending(r => r.Id).FirstOrDefaultAsync();
        if (dup is not null) return Conflict(new { error = "Đã có yêu cầu này đang chờ mẹ duyệt.", id = dup.Id });

        // Dọn: yêu cầu đã quyết định quá hạn giữ, yêu cầu chờ quá hạn, và chặn bảng phình ra.
        var decidedCutoff = now - RequestRules.DecidedRetention;
        await db.ChildRequests.Where(r => r.DeviceId == SubjectId && r.CreatedAt < decidedCutoff).ExecuteDeleteAsync();
        if (await db.ChildRequests.CountAsync(r => r.DeviceId == SubjectId) >= RequestRules.MaxRowsPerDevice)
            return StatusCode(StatusCodes.Status429TooManyRequests, new { error = "Quá nhiều yêu cầu." });

        var row = new ChildRequest { DeviceId = SubjectId, Kind = req.Kind, Payload = payload, CreatedAt = now };
        db.ChildRequests.Add(row);
        await db.SaveChangesAsync();
        return RequestDto(row);
    }

    /// <summary>Con xem kết quả một yêu cầu của chính nó. Của máy khác → 404.</summary>
    [HttpGet("requests/{id:int}")]
    public async Task<ActionResult<ChildRequestDto>> GetRequest(int id)
    {
        if (!await Touch()) return Unauthorized();
        var row = await db.ChildRequests.FirstOrDefaultAsync(r => r.Id == id && r.DeviceId == SubjectId);
        return row is null ? NotFound() : RequestDto(row);
    }

    internal static ChildRequestDto RequestDto(ChildRequest r) =>
        new(r.Id, r.DeviceId, r.Kind, r.Payload, r.Status, r.CreatedAt, r.DecidedAt);

    /// <summary>
    /// Máy con gửi app (tên + tên gói, không nội dung). <c>isNew</c> = true: app vừa cài, chờ mẹ duyệt (cài lại app đã gỡ
    /// cũng về chờ duyệt). Không có cờ: ghi nhận app, không ép gì. Thêm app mới, cập nhật nhãn, giữ FirstSeenAt.
    /// Máy con không thể tự đặt allowed/blocked.
    /// </summary>
    [HttpPost("apps")]
    public async Task<IActionResult> PostApps(PostAppsRequest req)
    {
        if (!await Touch()) return Unauthorized();
        var error = AppRules.Validate(req);
        if (error is not null) return BadRequest(new { error });
        var existing = await db.InstalledApps.Where(a => a.DeviceId == SubjectId).ToDictionaryAsync(a => a.PackageName);
        var items = req.Apps.DistinctBy(a => a.PackageName).ToList();
        if (existing.Count + items.Count(a => !existing.ContainsKey(a.PackageName)) > AppRules.MaxAppsPerDevice)
            return StatusCode(StatusCodes.Status429TooManyRequests, new { error = "Quá nhiều app." });
        foreach (var item in items)
        {
            var label = AppRules.CleanLabel(item.Label, item.PackageName);
            if (existing.TryGetValue(item.PackageName, out var row))
            {
                row.Label = label;
                if (item.IsNew == true && row.Status != AppRules.New)
                {
                    row.Status = AppRules.New; // cài lại: phải duyệt lại
                    row.DecidedAt = null;
                }
            }
            else
                db.InstalledApps.Add(new InstalledApp
                {
                    DeviceId = SubjectId, PackageName = item.PackageName, Label = label,
                    Status = item.IsNew == true ? AppRules.New : AppRules.Allowed,
                });
        }
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>Quyết định của mẹ (allowed/blocked) để máy con áp dụng. Chỉ tên gói + trạng thái.</summary>
    [HttpGet("apps/decisions")]
    public async Task<ActionResult<List<AppDecisionDto>>> AppDecisions()
    {
        if (!await Touch()) return Unauthorized();
        return await db.InstalledApps.Where(a => a.DeviceId == SubjectId && a.DecidedAt != null && a.Status != AppRules.New)
            .OrderByDescending(a => a.DecidedAt).Take(AppRules.MaxDecisionRows)
            .Select(a => new AppDecisionDto(a.PackageName, a.Status)).ToListAsync();
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
