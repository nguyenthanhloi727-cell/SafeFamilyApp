namespace SafeFamily.Api.Services;

/// <summary>Quy tắc vị trí (API-11): số ngày giữ (đã chốt 7) và thông báo khi mẹ tắt chia sẻ.</summary>
public static class LocationRules
{
    public static readonly TimeSpan Retention = TimeSpan.FromDays(7);
    public const string SharingOffError = "Đã tắt chia sẻ vị trí.";
}
