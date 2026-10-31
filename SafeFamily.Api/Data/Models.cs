using SafeFamily.Api.Services;

namespace SafeFamily.Api.Data;

public class Family
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>Tài khoản mẹ (phụ huynh). Bố thêm sau: nhiều Parent cùng FamilyId.</summary>
public class Parent
{
    public int Id { get; set; }
    public int FamilyId { get; set; }
    public Family? Family { get; set; }
    public string Email { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class RefreshToken
{
    public int Id { get; set; }
    public int ParentId { get; set; }
    /// <summary>Chỉ lưu SHA-256 của token, không lưu token gốc.</summary>
    public string TokenHash { get; set; } = "";
    public DateTime ExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }
}

/// <summary>Máy con. Thuộc đúng một gia đình; hủy ghép thì Revoked = true.</summary>
public class Device
{
    public int Id { get; set; }
    public int FamilyId { get; set; }
    public string Name { get; set; } = "";
    public DateTime PairedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastSeenAt { get; set; }
    public bool Revoked { get; set; }
    /// <summary>Phiên bản bộ hàng rào địa lý; mỗi lần mẹ ghi mới tăng 1.</summary>
    public int GeofenceVersion { get; set; }
}

/// <summary>Mã ghép đôi 6 số do mẹ tạo, có hạn dùng, dùng một lần.</summary>
public class Pairing
{
    public int Id { get; set; }
    public int FamilyId { get; set; }
    public string Code { get; set; } = "";
    public string DeviceName { get; set; } = "";
    public DateTime ExpiresAt { get; set; }
    public DateTime? UsedAt { get; set; }
}

/// <summary>Luật của một máy con. Json là gói luật do app Flutter định nghĩa, server chỉ lưu và đánh số phiên bản.</summary>
public class Policy
{
    public int Id { get; set; }
    public int DeviceId { get; set; }
    public int Version { get; set; }
    public string Json { get; set; } = "{}";
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>Lệnh tức thời (tạm dừng...). Máy con lấy khi polling rồi xác nhận.</summary>
public class Command
{
    public int Id { get; set; }
    public int DeviceId { get; set; }
    public string Type { get; set; } = "";
    public string PayloadJson { get; set; } = "{}";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? DoneAt { get; set; }
}

/// <summary>
/// Chỉ tên + tên gói, không nội dung. <see cref="Status"/> (API-07): <c>new</c> = con vừa cài, chờ mẹ duyệt;
/// <c>allowed</c>/<c>blocked</c> = mẹ đã quyết (<see cref="DecidedAt"/> có giá trị). Dòng con gửi không kèm cờ app mới là <c>allowed</c>
/// với <see cref="DecidedAt"/> = null (chưa ai quyết, máy con không bị ép gì).
/// </summary>
public class InstalledApp
{
    public int Id { get; set; }
    public int DeviceId { get; set; }
    public string PackageName { get; set; } = "";
    public string Label { get; set; } = "";
    public DateTime FirstSeenAt { get; set; } = DateTime.UtcNow;
    public string Status { get; set; } = "allowed";
    public DateTime? DecidedAt { get; set; }
}

/// <summary>Một điểm vị trí máy con gửi lên. Chỉ giữ vài ngày gần nhất.</summary>
public class LocationPoint
{
    public long Id { get; set; }
    public int DeviceId { get; set; }
    public double Lat { get; set; }
    public double Lng { get; set; }
    public double Accuracy { get; set; }
    /// <summary>Thời điểm máy con đo (UTC).</summary>
    public DateTime Time { get; set; }
}

/// <summary>Hàng rào địa lý: tâm + bán kính (mét).</summary>
public class Geofence
{
    public int Id { get; set; }
    public int DeviceId { get; set; }
    public string Name { get; set; } = "";
    public double Lat { get; set; }
    public double Lng { get; set; }
    public double RadiusM { get; set; }
}

/// <summary>Máy con vào/ra một hàng rào. Type = "enter" | "exit".</summary>
public class GeofenceEvent
{
    public long Id { get; set; }
    public int DeviceId { get; set; }
    public int GeofenceId { get; set; }
    public string GeofenceName { get; set; } = "";
    public string Type { get; set; } = "";
    public DateTime Time { get; set; }
}

/// <summary>
/// Trạng thái máy con báo mỗi lượt đồng bộ (API-09). Mỗi máy một dòng, ghi đè. Chỉ có các trường
/// dưới đây: không có nội dung hay app đang dùng. LastSeenAt nằm ở <see cref="Device"/>.
/// </summary>
public class DeviceStatus
{
    public int Id { get; set; }
    public int DeviceId { get; set; }
    public int? BatteryPercent { get; set; }
    /// <summary>Phiên bản luật máy con đã áp dụng (khác Policy.Version = mẹ đã đẩy mà con chưa nhận).</summary>
    public int PolicyVersion { get; set; }
    public bool IsPaused { get; set; }
    public bool StudyActive { get; set; }
    /// <summary>Mảng JSON các id quyền còn thiếu, ví dụ ["accessibility","device_admin"].</summary>
    public string PermissionsMissingJson { get; set; } = "[]";
    public string? AppVersion { get; set; }
    /// <summary>Mảng JSON {package, until} các app đang mở tạm; giữ để mẹ bấm "chặn lại ngay".</summary>
    public string TempUnlockedJson { get; set; } = "[]";
    public DateTime ReportedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Yêu cầu của máy con (API-06): xin thêm giờ hoặc báo "đã học xong". Chỉ có loại yêu cầu và số phút xin,
/// không có nội dung hay app đang dùng. Mẹ duyệt/từ chối thì server tạo lệnh tương ứng.
/// </summary>
public class ChildRequest
{
    public int Id { get; set; }
    public int DeviceId { get; set; }
    /// <summary>"extra_time" | "study_done".</summary>
    public string Kind { get; set; } = "";
    /// <summary>JSON: extra_time = {"minutes":N}, study_done = {}.</summary>
    public string Payload { get; set; } = "{}";
    /// <summary>"pending" | "approved" | "rejected".</summary>
    public string Status { get; set; } = RequestRules.Pending;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? DecidedAt { get; set; }
}

/// <summary>
/// Báo cáo sử dụng một ngày của máy con (API-08). Chỉ phút theo app, không nội dung, không vị trí.
/// Khóa duy nhất (DeviceId, Date): máy con gửi lại cùng ngày thì ghi đè, không trùng.
/// </summary>
public class UsageDay
{
    public int Id { get; set; }
    public int DeviceId { get; set; }
    /// <summary>Ngày theo lịch trên máy con (không kèm giờ).</summary>
    public DateOnly Date { get; set; }
    public int TotalMinutes { get; set; }
    /// <summary>Số lần màn chặn hiện lên trong ngày.</summary>
    public int Blocks { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public List<UsageApp> Apps { get; set; } = [];
}

/// <summary>Phút dùng một app trong một ngày (<see cref="UsageDay"/>).</summary>
public class UsageApp
{
    public int Id { get; set; }
    public int UsageDayId { get; set; }
    public string Package { get; set; } = "";
    public int Minutes { get; set; }
}
