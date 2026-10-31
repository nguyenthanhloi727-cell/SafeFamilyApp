using System.Security.Cryptography;

namespace SafeFamily.Api.Services;

/// <summary>Luật người giám hộ thứ 2 (API-02). Đã chốt 2026-10-31: tối đa 2 người, chỉ chủ mời/xóa, mã hạn 30 phút dùng một lần.</summary>
public static class FamilyRules
{
    public const int MaxGuardians = 2;
    public const int CodeLength = 8;
    public static readonly TimeSpan InviteLife = TimeSpan.FromMinutes(30);

    public static string NewCode() => RandomNumberGenerator.GetInt32(0, 100_000_000).ToString("D8");
}
