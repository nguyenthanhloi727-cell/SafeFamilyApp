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

    /// <summary>
    /// Mẹ đổi tên máy con (API-01): body <c>{"name":"..."}</c>, 1–50 ký tự sau khi cắt khoảng trắng, không có ký tự điều khiển;
    /// sai → 400. Gia đình khác hoặc máy đã hủy ghép → 404.
    /// </summary>
    [HttpPatch("{id:int}")]
    public async Task<ActionResult<DeviceDto>> Rename(int id, RenameDeviceRequest req)
    {
        var device = await Own(id);
        if (device is null) return NotFound();
        var name = DeviceRules.CleanName(req.Name);
        if (name is null) return BadRequest(new { error = "Tên máy phải dài 1–50 ký tự và không có ký tự điều khiển." });
        device.Name = name;
        await db.SaveChangesAsync();
        return new DeviceDto(device.Id, device.Name, device.PairedAt, device.LastSeenAt);
    }

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

    /// <summary>
    /// Ghi luật. Phiên bản mẹ gửi (ExpectedVersion) phải bằng phiên bản hiện tại, lệch thì 409.
    /// Nếu luật có <c>contacts</c> (số SOS, API-13): tối đa 3 mục, nhãn 1–30 ký tự, số 9–12 chữ số; sai thì 400.
    /// </summary>
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
            var bad = PolicyRules.Validate(doc.RootElement); // contacts SOS (API-13)
            if (bad is not null) return BadRequest(new { error = bad });
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

    /// <summary>
    /// Báo cáo sử dụng của máy con (API-08): <c>from</c>/<c>to</c> dạng yyyy-MM-dd (mặc định 7 ngày gần nhất theo ngày UTC),
    /// tối đa 90 ngày, cũ nhất trước. Sai định dạng / from &gt; to / quá 90 ngày → 400. Gia đình khác hoặc máy hủy ghép → 404.
    /// </summary>
    [HttpGet("{id:int}/usage")]
    public async Task<ActionResult<List<UsageDayDto>>> Usage(int id, [FromQuery] string? from = null, [FromQuery] string? to = null)
    {
        if (await Own(id) is null) return NotFound();
        var end = DateOnly.FromDateTime(DateTime.UtcNow);
        if (to is not null && !UsageRules.TryParseDate(to, out end)) return BadRequest(new { error = "to không hợp lệ." });
        var start = end.AddDays(-6);
        if (from is not null && !UsageRules.TryParseDate(from, out start)) return BadRequest(new { error = "from không hợp lệ." });
        if (start > end) return BadRequest(new { error = "from phải không sau to." });
        if (end.DayNumber - start.DayNumber + 1 > UsageRules.MaxRangeDays) return BadRequest(new { error = "Khoảng ngày quá dài." });
        var rows = await db.UsageDays.Where(u => u.DeviceId == id && u.Date >= start && u.Date <= end)
            .OrderBy(u => u.Date).Include(u => u.Apps).AsNoTracking().ToListAsync();
        return rows.Select(u => new UsageDayDto(UsageRules.Format(u.Date), u.TotalMinutes, u.Blocks,
            u.Apps.ToDictionary(a => a.Package, a => a.Minutes))).ToList();
    }

    /// <summary>
    /// Cảnh báo của máy con (API-10), cũ trước, tối đa 100 (như geofence-events): không có <c>afterId</c> thì lấy 100 cảnh báo
    /// MỚI nhất, có thì 100 cảnh báo kế sau mốc để dò theo con trỏ không sót. Gia đình khác / máy đã hủy ghép → 404.
    /// </summary>
    [HttpGet("{id:int}/alerts")]
    public async Task<ActionResult<List<AlertDto>>> Alerts(int id, [FromQuery] int afterId = 0)
    {
        if (await Own(id) is null) return NotFound();
        var q = db.Alerts.Where(a => a.DeviceId == id && a.Id > afterId);
        var rows = afterId <= 0
            ? (await q.OrderByDescending(a => a.Id).Take(AlertRules.MaxListRows).ToListAsync()).AsEnumerable().Reverse().ToList()
            : await q.OrderBy(a => a.Id).Take(AlertRules.MaxListRows).ToListAsync();
        return rows.Select(AlertRules.ToDto).ToList();
    }

    /// <summary>Cờ chia sẻ vị trí của máy con (API-11). Gia đình khác / máy hủy ghép → 404.</summary>
    [HttpGet("{id:int}/location-sharing")]
    public async Task<ActionResult<LocationSharingDto>> GetLocationSharing(int id)
    {
        var device = await Own(id);
        return device is null ? NotFound() : new LocationSharingDto(device.LocationSharing);
    }

    /// <summary>
    /// Mẹ bật/tắt chia sẻ vị trí (API-11), body <c>{"enabled":true|false}</c> (thiếu / sai kiểu → 400). Chỉ đổi cờ:
    /// lịch sử đã có giữ nguyên, muốn xóa dùng <c>DELETE {id}/locations</c>. Máy con nhận ở lượt đồng bộ kế.
    /// </summary>
    [HttpPut("{id:int}/location-sharing")]
    public async Task<ActionResult<LocationSharingDto>> PutLocationSharing(int id, PutLocationSharingRequest req)
    {
        var device = await Own(id);
        if (device is null) return NotFound();
        device.LocationSharing = req.Enabled!.Value;
        await db.SaveChangesAsync();
        return new LocationSharingDto(device.LocationSharing);
    }

    /// <summary>Xóa toàn bộ lịch sử vị trí của máy con (API-11). Không đụng hàng rào và sự kiện vào/ra.</summary>
    [HttpDelete("{id:int}/locations")]
    public async Task<IActionResult> DeleteLocations(int id)
    {
        if (await Own(id) is null) return NotFound();
        await db.LocationPoints.Where(l => l.DeviceId == id).ExecuteDeleteAsync();
        return NoContent();
    }

    /// <summary>Vị trí mới nhất của máy con (204 nếu chưa có). Mẹ đã tắt chia sẻ → 403 kèm <c>locationSharing:false</c>.</summary>
    [HttpGet("{id:int}/location")]
    public async Task<ActionResult<LocationDto>> LastLocation(int id)
    {
        var device = await Own(id);
        if (device is null) return NotFound();
        if (!device.LocationSharing) return SharingOff();
        var last = await db.LocationPoints.Where(l => l.DeviceId == id).OrderByDescending(l => l.Time)
            .Select(l => new LocationDto(l.Lat, l.Lng, l.Accuracy, l.Time)).FirstOrDefaultAsync();
        return last is null ? NoContent() : last;
    }

    [HttpGet("{id:int}/locations")]
    public async Task<ActionResult<List<LocationDto>>> LocationHistory(int id)
    {
        var device = await Own(id);
        if (device is null) return NotFound();
        if (!device.LocationSharing) return SharingOff();
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

    ObjectResult SharingOff() =>
        StatusCode(StatusCodes.Status403Forbidden, new { error = LocationRules.SharingOffError, locationSharing = false });

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
    /// <summary>Máy con xem tên máy, tên gia đình và phiên bản luật hiện có trên server (API-01). Không lộ email mẹ.</summary>
    [HttpGet]
    public async Task<ActionResult<DeviceMeDto>> Me()
    {
        if (!await Touch()) return Unauthorized();
        var device = await db.Devices.AsNoTracking().FirstAsync(d => d.Id == SubjectId);
        var family = await db.Families.AsNoTracking().Where(f => f.Id == device.FamilyId).Select(f => f.Name).FirstOrDefaultAsync();
        var version = await db.Policies.Where(p => p.DeviceId == device.Id).Select(p => p.Version).FirstOrDefaultAsync();
        return new DeviceMeDto(device.Id, device.Name, family ?? "", device.PairedAt, version);
    }

    /// <summary>Cài đặt do mẹ đặt mà máy con cần biết (API-11: chia sẻ vị trí). Mỗi lượt đồng bộ kéo một lần.</summary>
    [HttpGet("settings")]
    public async Task<ActionResult<DeviceSettingsDto>> Settings()
    {
        if (!await Touch()) return Unauthorized();
        var device = await db.Devices.AsNoTracking().FirstAsync(d => d.Id == SubjectId);
        return new DeviceSettingsDto(device.LocationSharing);
    }

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

    /// <summary>
    /// Gửi lô vị trí. Bỏ điểm có thời gian ở tương lai quá 5 phút; xóa điểm cũ hơn LocationRules.Retention.
    /// Mẹ đã tắt chia sẻ (API-11) → 403, KHÔNG lưu gì; máy con coi là bỏ hàng chờ.
    /// </summary>
    [HttpPost("locations")]
    public async Task<IActionResult> PostLocations(PostLocationsRequest req)
    {
        if (!await Touch()) return Unauthorized();
        if (!await db.Devices.AnyAsync(d => d.Id == SubjectId && d.LocationSharing))
            return StatusCode(StatusCodes.Status403Forbidden, new { error = LocationRules.SharingOffError, locationSharing = false });
        if (req.Points.Count > 500) return BadRequest(new { error = "Quá nhiều điểm." });
        var now = DateTime.UtcNow;
        var cutoff = now - LocationRules.Retention;
        // Điểm quá hạn giữ không được lưu (API-15: trước đây lưu rồi mới bị xóa ở lượt gửi sau).
        foreach (var p in req.Points.Where(p => p.Time.ToUniversalTime() < now.AddMinutes(5) && p.Time.ToUniversalTime() >= cutoff))
            db.LocationPoints.Add(new LocationPoint
            {
                DeviceId = SubjectId, Lat = p.Lat, Lng = p.Lng, Accuracy = p.Accuracy, Time = p.Time.ToUniversalTime(),
            });
        await db.LocationPoints.Where(l => l.DeviceId == SubjectId && l.Time < cutoff).ExecuteDeleteAsync();
        await db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// Máy con gửi báo cáo sử dụng theo ngày (API-08, lô ≤31 ngày, upsert theo (máy, ngày)). Chỉ phút theo app.
    /// Dọn dữ liệu cũ hơn 90 ngày của máy này mỗi lần gửi.
    /// </summary>
    [HttpPost("usage")]
    public async Task<IActionResult> PostUsage(PostUsageRequest req)
    {
        if (!await Touch()) return Unauthorized();
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var error = UsageRules.Validate(req, today);
        if (error is not null) return BadRequest(new { error });

        var dates = req.Days.Select(d => { UsageRules.TryParseDate(d.Date, out var x); return x; }).ToList();
        var existing = await db.UsageDays.Where(u => u.DeviceId == SubjectId && dates.Contains(u.Date))
            .Include(u => u.Apps).ToDictionaryAsync(u => u.Date);
        var now = DateTime.UtcNow;
        for (var i = 0; i < req.Days.Count; i++)
        {
            var item = req.Days[i];
            if (!existing.TryGetValue(dates[i], out var row))
                db.UsageDays.Add(row = new UsageDay { DeviceId = SubjectId, Date = dates[i] });
            else
                db.UsageApps.RemoveRange(row.Apps);
            row.TotalMinutes = item.TotalMinutes;
            row.Blocks = item.Blocks;
            row.UpdatedAt = now;
            row.Apps = item.Apps.Select(kv => new UsageApp { Package = kv.Key, Minutes = kv.Value }).ToList();
        }
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException) { return Conflict(new { error = "Đang gửi trùng, thử lại sau." }); } // hai lô cùng lúc vi phạm khóa duy nhất
        var cutoff = today.AddDays(-UsageRules.RetentionDays);
        await db.UsageDays.Where(u => u.DeviceId == SubjectId && u.Date < cutoff).ExecuteDeleteAsync();
        return NoContent();
    }

    /// <summary>
    /// Máy con báo sự kiện tamper (API-10): <c>time_changed</c>, <c>app_uninstall_attempt</c>, <c>accessibility_off</c>,
    /// <c>device_admin_off</c>, <c>permission_missing</c> (<c>offline</c> do server tự tạo). <c>detail</c> chỉ là mã/số ngắn.
    /// Cùng loại trong 10 phút quanh thời điểm xảy ra → 409 kèm <c>id</c> của dòng đã có (máy con coi như đã gửi).
    /// Quá 200 dòng thì xóa dòng cũ nhất; dòng quá 30 ngày bị dọn mỗi lần gửi.
    /// </summary>
    [HttpPost("alerts")]
    public async Task<ActionResult<AlertDto>> PostAlert(PostAlertRequest req)
    {
        if (!await Touch()) return Unauthorized();
        var now = DateTime.UtcNow;
        var error = AlertRules.Validate(req, now, out var at);
        if (error is not null) return BadRequest(new { error });

        var lo = at - AlertRules.DedupWindow;
        var hi = at + AlertRules.DedupWindow;
        var dup = await db.Alerts.Where(a => a.DeviceId == SubjectId && a.Kind == req.Kind && a.CreatedAt > lo && a.CreatedAt < hi)
            .OrderByDescending(a => a.Id).FirstOrDefaultAsync();
        if (dup is not null) return Conflict(new { error = "Đã có cảnh báo cùng loại gần đây.", id = dup.Id });

        await AlertRules.TrimAsync(db, SubjectId, now);
        var row = new Alert { DeviceId = SubjectId, Kind = req.Kind, Detail = string.IsNullOrEmpty(req.Detail) ? null : req.Detail, CreatedAt = at };
        db.Alerts.Add(row);
        await db.SaveChangesAsync();
        return AlertRules.ToDto(row);
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
