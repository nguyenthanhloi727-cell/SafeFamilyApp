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

/// <summary>Chỉ tên + tên gói, không nội dung.</summary>
public class InstalledApp
{
    public int Id { get; set; }
    public int DeviceId { get; set; }
    public string PackageName { get; set; } = "";
    public string Label { get; set; } = "";
    public DateTime FirstSeenAt { get; set; } = DateTime.UtcNow;
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
