using System.Net;
using System.Net.Mail;
using System.Security.Cryptography;
using System.Text;

namespace SafeFamily.Api.Services;

/// <summary>Quy tắc mã đặt lại mật khẩu (API-03): mã 6 số, hạn 30 phút, dùng một lần, tối đa 5 lần thử sai.</summary>
public static class PasswordResetRules
{
    public static readonly TimeSpan Life = TimeSpan.FromMinutes(30);
    /// <summary>Sau từng ấy lần nhập sai thì mã bị hủy (6 số chỉ có 1 triệu khả năng, chặn đoán mò).</summary>
    public const int MaxAttempts = 5;
    /// <summary>Xin mã lần nữa trong khoảng này thì bỏ qua (chống dội thư vào hộp mail của mẹ).</summary>
    public static readonly TimeSpan Cooldown = TimeSpan.FromSeconds(60);

    public static string NewCode() => RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");

    /// <summary>HMAC theo khóa JWT + id mẹ: lộ DB cũng không dò ngược được mã 6 số bằng băm thường.</summary>
    public static string Hash(string code, int parentId, string key) =>
        Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(key),
            Encoding.UTF8.GetBytes($"{parentId}:{code}"))).ToLowerInvariant();
}

/// <summary>
/// Cấu hình thư (section "Smtp"). Mật khẩu KHÔNG nằm trong git: đặt qua biến môi trường <c>Smtp__Password</c> hoặc
/// appsettings.Local.json. TODO(verify): host/port/tài khoản/From thật của MyASP.net chưa được xác nhận.
/// </summary>
public class SmtpOptions
{
    public string Host { get; set; } = "";
    public int Port { get; set; } = 587;
    /// <summary>STARTTLS (cổng 587). <c>SmtpClient</c> không hỗ trợ SSL ngầm định ở cổng 465.</summary>
    public bool UseSsl { get; set; } = true;
    public string User { get; set; } = "";
    public string Password { get; set; } = "";
    public string From { get; set; } = "";
    /// <summary>Chỉ để test: có giá trị thì thư được ghi thành file .eml vào thư mục này thay vì gửi qua mạng.</summary>
    public string PickupDirectory { get; set; } = "";

    public bool IsConfigured => From.Length > 0 && (PickupDirectory.Length > 0 || Host.Length > 0);
}

public interface IEmailSender
{
    /// <summary>Không bao giờ ném lỗi (ghi log): người gọi không được biết thư có tới hay không.</summary>
    Task SendAsync(string to, string subject, string body);
}

public class SmtpEmailSender(SmtpOptions opt, ILogger<SmtpEmailSender> log) : IEmailSender
{
    public async Task SendAsync(string to, string subject, string body)
    {
        if (!opt.IsConfigured)
        {
            log.LogWarning("Chưa cấu hình Smtp (Host/From): không gửi được thư đặt lại mật khẩu.");
            return;
        }
        try
        {
            using var client = new SmtpClient();
            if (opt.PickupDirectory.Length > 0)
            {
                Directory.CreateDirectory(opt.PickupDirectory);
                client.DeliveryMethod = SmtpDeliveryMethod.SpecifiedPickupDirectory;
                client.PickupDirectoryLocation = opt.PickupDirectory;
            }
            else
            {
                client.Host = opt.Host;
                client.Port = opt.Port;
                client.EnableSsl = opt.UseSsl;
                if (opt.User.Length > 0) client.Credentials = new NetworkCredential(opt.User, opt.Password);
            }
            using var msg = new MailMessage(opt.From, to, subject, body)
            {
                BodyEncoding = Encoding.UTF8,
                SubjectEncoding = Encoding.UTF8,
            };
            await client.SendMailAsync(msg);
        }
        catch (Exception e)
        {
            log.LogError(e, "Gửi thư đặt lại mật khẩu thất bại.");
        }
    }
}
