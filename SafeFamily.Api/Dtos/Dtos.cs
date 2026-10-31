using System.ComponentModel.DataAnnotations;

namespace SafeFamily.Api.Dtos;

public record RegisterRequest([Required, EmailAddress, MaxLength(256)] string Email,
                              [Required, MinLength(8), MaxLength(128)] string Password,
                              [MaxLength(100)] string? FamilyName);
public record LoginRequest([Required] string Email, [Required] string Password);
public record RefreshRequest([Required] string RefreshToken);
public record AuthResponse(string AccessToken, string RefreshToken, int FamilyId);

public record CreateCodeRequest([MaxLength(100)] string? DeviceName);
public record CodeResponse(string Code, DateTime ExpiresAt);
public record ClaimRequest([Required, StringLength(6, MinimumLength = 6)] string Code);
public record ClaimResponse(string DeviceToken, int DeviceId, string DeviceName);

public record DeviceDto(int Id, string Name, DateTime PairedAt, DateTime? LastSeenAt);

public record PolicyDto(int Version, string Json, DateTime UpdatedAt);
/// <summary>ExpectedVersion = phiên bản mẹ đang sửa từ đó; lệch thì 409.</summary>
public record PutPolicyRequest([Required] string Json, int ExpectedVersion);

public record CreateCommandRequest([Required, MaxLength(50)] string Type, string? PayloadJson);
public record CommandDto(int Id, string Type, string PayloadJson, DateTime CreatedAt, DateTime? DoneAt);

/// <summary>IsNew = true: app vừa cài, chờ mẹ duyệt (API-07). Máy con không thể tự đặt allowed/blocked.</summary>
public record AppItem([Required, MaxLength(256)] string PackageName, [Required, MaxLength(200)] string Label, bool? IsNew = null);
public record PostAppsRequest([Required] List<AppItem> Apps);
public record InstalledAppDto(int Id, string PackageName, string Label, DateTime FirstSeenAt, string Status, DateTime? DecidedAt);
/// <summary>Mẹ đặt trạng thái một app: <c>allowed</c> hoặc <c>blocked</c> (không đặt lại về <c>new</c>).</summary>
public record PutAppStatusRequest([Required, MaxLength(10)] string Status);
/// <summary>Quyết định của mẹ mà máy con kéo về (chỉ tên gói + allowed/blocked).</summary>
public record AppDecisionDto(string PackageName, string Status);

public record LocationItem([Range(-90.0, 90.0)] double Lat, [Range(-180.0, 180.0)] double Lng, [Range(0.0, 100000.0)] double Accuracy, DateTime Time);
public record PostLocationsRequest([Required] List<LocationItem> Points);
public record LocationDto(double Lat, double Lng, double Accuracy, DateTime Time);

public record GeofenceItem(int Id, [Required, MaxLength(100)] string Name,
                           [Range(-90.0, 90.0)] double Lat, [Range(-180.0, 180.0)] double Lng,
                           [Range(100.0, 10000.0)] double RadiusM);
public record PutGeofencesRequest([Required] List<GeofenceItem> Geofences, int ExpectedVersion);
public record GeofencesDto(int Version, List<GeofenceItem> Geofences);

public record GeofenceEventItem(int GeofenceId, [Required, RegularExpression("enter|exit")] string Type, DateTime Time);
public record PostGeofenceEventsRequest([Required] List<GeofenceEventItem> Events);
public record GeofenceEventDto(long Id, int GeofenceId, string GeofenceName, string Type, DateTime Time);

// ---- Trạng thái máy con (API-09). Chỉ các trường này, không nội dung/app đang dùng. ----
public record TempUnlockItem([Required, MaxLength(200)] string Package, DateTime Until);
public record PutStatusRequest([Range(0, 100)] int? BatteryPercent, [Range(0, int.MaxValue)] int PolicyVersion,
                               bool IsPaused, bool StudyActive,
                               List<string>? PermissionsMissing, [MaxLength(32)] string? AppVersion,
                               List<TempUnlockItem>? TempUnlocked);
public record DeviceStatusDto(DateTime? LastSeenAt, DateTime? ReportedAt, int? BatteryPercent, int PolicyVersion,
                              bool IsPaused, bool StudyActive, List<string> PermissionsMissing, string? AppVersion,
                              List<TempUnlockItem> TempUnlocked);

// ---- Yêu cầu của máy con (API-06). Chỉ loại yêu cầu + số phút xin. ----
public record CreateChildRequest([Required, MaxLength(20)] string Kind, string? PayloadJson);
public record ChildRequestDto(int Id, int DeviceId, string Kind, string Payload, string Status,
                              DateTime CreatedAt, DateTime? DecidedAt);
/// <summary>Decision = "approved" | "rejected". Minutes chỉ dùng khi duyệt extra_time (bỏ trống = số phút con xin).</summary>
// ---- Báo cáo sử dụng (API-08). Chỉ phút theo app theo ngày. ----
/// <summary>Date = "yyyy-MM-dd"; Apps = tên gói → phút.</summary>
public record UsageDayItem([Required] string Date, int TotalMinutes, int Blocks, [Required] Dictionary<string, int> Apps);
public record PostUsageRequest([Required] List<UsageDayItem> Days);
public record UsageDayDto(string Date, int TotalMinutes, int Blocks, Dictionary<string, int> Apps);

// ---- Cảnh báo cho mẹ (API-10). Chỉ loại sự kiện, mã/số ngắn và thời điểm. ----
/// <summary>OccurredAt = lúc xảy ra (UTC); bỏ trống = bây giờ. Máy con gửi bù lúc offline thì điền giờ thật.</summary>
public record PostAlertRequest([Required, MaxLength(30)] string Kind, [MaxLength(32)] string? Detail, DateTime? OccurredAt);
public record AlertDto(int Id, string Kind, string? Detail, DateTime CreatedAt, DateTime? ReadAt);

public record DecideRequest([Required, MaxLength(10)] string Decision, int? Minutes);
