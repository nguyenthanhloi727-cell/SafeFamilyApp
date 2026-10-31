using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace SafeFamily.Api.Services;

public class JwtOptions
{
    public string Key { get; set; } = "";
    public string Issuer { get; set; } = "SafeFamily.Api";
    public string Audience { get; set; } = "SafeFamily.App";
}

public static class Roles
{
    public const string Parent = "parent";
    public const string Device = "device";
}

public class TokenService(JwtOptions opt)
{
    public string ParentAccessToken(int parentId, int familyId) =>
        Create([new("sub", parentId.ToString()), new("fam", familyId.ToString()),
                new(ClaimTypes.Role, Roles.Parent)], TimeSpan.FromMinutes(30));

    public string DeviceToken(int deviceId, int familyId) =>
        Create([new("sub", deviceId.ToString()), new("fam", familyId.ToString()),
                new(ClaimTypes.Role, Roles.Device)], TimeSpan.FromDays(365));

    string Create(Claim[] claims, TimeSpan life)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(opt.Key));
        var token = new JwtSecurityToken(opt.Issuer, opt.Audience, claims,
            expires: DateTime.UtcNow.Add(life),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public static string NewRefreshToken() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

    public static string Hash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
}

/// <summary>PBKDF2-SHA256, định dạng "iter.salt.hash".</summary>
public static class PasswordHasher
{
    const int Iterations = 120_000;

    public static string Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, 32);
        return $"{Iterations}.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(hash)}";
    }

    public static bool Verify(string password, string stored)
    {
        var parts = stored.Split('.');
        if (parts.Length != 3 || !int.TryParse(parts[0], out var iter)) return false;
        var salt = Convert.FromBase64String(parts[1]);
        var expected = Convert.FromBase64String(parts[2]);
        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iter, HashAlgorithmName.SHA256, expected.Length);
        return CryptographicOperations.FixedTimeEquals(actual, expected);
    }
}
