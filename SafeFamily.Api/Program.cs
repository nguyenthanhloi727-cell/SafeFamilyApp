using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;
using SafeFamily.Api.Data;
using SafeFamily.Api.Services;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// Bí mật (chuỗi kết nối, khóa JWT) KHÔNG nằm trong git: đặt qua appsettings.Local.json
// (đã .gitignore), biến môi trường (ConnectionStrings__Default, Jwt__Key) hoặc cấu hình server.
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: false);

// API-14: log lỗi ra file (Serilog). Logging:File:Path mặc định logs/safefamily-.log (xoay theo ngày, giữ 14 file);
// Logging:File:Enabled=false để tắt (test tích hợp). Chỉ ghi lỗi/cảnh báo của server, KHÔNG ghi body hay token.
builder.Host.UseSerilog((ctx, _, cfg) =>
{
    cfg.ReadFrom.Configuration(ctx.Configuration)
        .MinimumLevel.Information()
        .MinimumLevel.Override("Microsoft.AspNetCore", Serilog.Events.LogEventLevel.Warning)
        .MinimumLevel.Override("Microsoft.EntityFrameworkCore", Serilog.Events.LogEventLevel.Warning)
        .Enrich.FromLogContext()
        .WriteTo.Console();
    if (ctx.Configuration.GetValue("Logging:File:Enabled", true))
        cfg.WriteTo.File(ctx.Configuration["Logging:File:Path"] ?? "logs/safefamily-.log",
            rollingInterval: RollingInterval.Day, retainedFileCountLimit: 14, shared: true);
});

var connection = builder.Configuration.GetConnectionString("Default");
var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
if (string.IsNullOrWhiteSpace(connection))
    throw new InvalidOperationException("Thiếu ConnectionStrings:Default (xem docs/API_TIEN_TRINH.md, mục Cấu hình).");
if (jwt.Key.Length < 32)
    throw new InvalidOperationException("Jwt:Key phải dài từ 32 ký tự (xem docs/API_TIEN_TRINH.md, mục Cấu hình).");

builder.Services.AddDbContext<AppDb>(o => o.UseSqlServer(connection));
builder.Services.AddSingleton(jwt);
builder.Services.AddSingleton<TokenService>();
builder.Services.AddSingleton(builder.Configuration.GetSection("Smtp").Get<SmtpOptions>() ?? new SmtpOptions());
builder.Services.AddSingleton<IEmailSender, SmtpEmailSender>();
builder.Services.AddControllers().ConfigureApiBehaviorOptions(o =>
{
    // 400 do kiểm kiểu/độ dài: ProblemDetails + trường "error" để app Flutter (đọc m['error']) vẫn hiện được câu báo.
    o.InvalidModelStateResponseFactory = ctx =>
    {
        var factory = ctx.HttpContext.RequestServices.GetRequiredService<ProblemDetailsFactory>();
        var pd = factory.CreateValidationProblemDetails(ctx.HttpContext, ctx.ModelState, StatusCodes.Status400BadRequest);
        pd.Extensions["error"] = "Thông tin chưa hợp lệ.";
        return new BadRequestObjectResult(pd) { ContentTypes = { "application/problem+json" } };
    };
});
// API-14: lỗi 5xx / 404 / 429 / 413 không có thân thì trả ProblemDetails thống nhất (kèm "error" cho app, "traceId" để tra log).
builder.Services.AddProblemDetails(o => o.CustomizeProblemDetails = ctx =>
{
    var pd = ctx.ProblemDetails;
    pd.Extensions["error"] = pd.Status switch
    {
        400 => "Thông tin chưa hợp lệ.",
        401 => "Phiên đăng nhập hết hạn, hãy đăng nhập lại.",
        403 => "Tài khoản này không được phép làm việc đó.",
        404 => "Không tìm thấy.",
        413 => "Dữ liệu gửi lên quá lớn.",
        429 => "Thử quá nhiều lần, hãy đợi một lúc.",
        >= 500 => "Máy chủ gặp lỗi, thử lại sau.",
        _ => pd.Title ?? "Lỗi.",
    };
    pd.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier;
});
builder.Services.AddHostedService<OfflineAlertService>(); // API-10: cảnh báo mẹ khi máy con mất kết nối
builder.Services.AddHostedService<DataCleanupService>(); // API-14: dọn dữ liệu cũ định kỳ

// CORS chặt: app di động không cần CORS và Swagger cùng gốc, nên mặc định KHÔNG cho trang web nào gọi chéo gốc.
// Muốn cho một trang web cụ thể thì đặt Cors:Origins (mảng, ví dụ Cors__Origins__0=https://tenmien.com).
var corsOrigins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
if (corsOrigins.Length > 0)
    builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.WithOrigins(corsOrigins)
        .WithMethods("GET", "POST", "PUT", "DELETE")
        .WithHeaders("Authorization", "Content-Type", "X-App-Version")));

// Sau proxy ngược (MyASP.net/IIS): đặt Proxy:ForwardedHeaders=true để HTTPS redirect và giới hạn tần suất theo IP thật.
// TODO(verify): MyASP.net có tự gửi X-Forwarded-* không; chỉ bật khi đã kiểm, vì header này giả được nếu server nhận thẳng từ Internet.
var forwarded = builder.Configuration.GetValue("Proxy:ForwardedHeaders", false);
var maxBodyBytes = builder.Configuration.GetValue("Limits:MaxBodyBytes", PlatformRules.DefaultMaxBodyBytes);
builder.WebHost.ConfigureKestrel(k => k.Limits.MaxRequestBodySize = maxBodyBytes);

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.MapInboundClaims = false; // giữ nguyên "sub", "fam"
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Issuer,
            ValidateAudience = true,
            ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            ValidateLifetime = true,
            RequireExpirationTime = true,
            RequireSignedTokens = true,
            ValidAlgorithms = [SecurityAlgorithms.HmacSha256], // khóa đối xứng HS256, từ chối thuật toán khác
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Key)),
            RoleClaimType = System.Security.Claims.ClaimTypes.Role,
            ClockSkew = TimeSpan.FromSeconds(30),
        };
    });
builder.Services.AddAuthorization();

// RateLimit:AuthPerMinute chỉ để nâng trần khi chạy smoke.sh (mặc định 10, giữ nguyên khi chạy thật).
var authPerMinute = builder.Configuration.GetValue("RateLimit:AuthPerMinute", 10);
var claimPer10Min = builder.Configuration.GetValue("RateLimit:ClaimPer10Min", 5); // API-15: test tích hợp nâng trần
// API-14: trần cho endpoint của máy con (polling 5 phút/lần nên 240/phút/máy là rất rộng). Nâng khi chạy smoke.sh.
var devicePerMinute = builder.Configuration.GetValue("RateLimit:DevicePerMinute", 240);

// Giới hạn tần suất theo IP: đăng nhập/đăng ký, và nhập mã ghép đôi (mã chỉ 6 số nên chặn đoán mò).
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.OnRejected = async (ctx, ct) =>
    {
        ctx.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        if (ctx.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retry))
            ctx.HttpContext.Response.Headers.RetryAfter = ((int)retry.TotalSeconds).ToString();
        await Results.Problem(statusCode: 429, title: "Quá nhiều yêu cầu.").ExecuteAsync(ctx.HttpContext);
    };
    o.AddPolicy("device", ctx => RateLimitPartition.GetFixedWindowLimiter(
        "d:" + (ctx.User.FindFirst("sub")?.Value ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "?"),
        _ => new FixedWindowRateLimiterOptions { PermitLimit = devicePerMinute, Window = TimeSpan.FromMinutes(1) }));
    o.AddPolicy("auth", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "?",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = authPerMinute, Window = TimeSpan.FromMinutes(1) }));
    o.AddPolicy("claim", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "?",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = claimPer10Min, Window = TimeSpan.FromMinutes(10) }));
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(o =>
{
    o.SwaggerDoc("v1", new OpenApiInfo { Title = "SafeFamily API", Version = "v1" });
    // Nút Authorize: dán access token (chỉ phần token, không gõ "Bearer").
    o.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "Dán access token từ /api/auth/login (mẹ) hoặc /api/pairing/claim (con).",
    });
    o.AddSecurityRequirement(doc => new OpenApiSecurityRequirement
    {
        [new OpenApiSecuritySchemeReference("Bearer", doc)] = [],
    });
});

var app = builder.Build();

if (forwarded)
{
    var fo = new ForwardedHeadersOptions { ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto };
    fo.KnownIPNetworks.Clear();
    fo.KnownProxies.Clear();
    app.UseForwardedHeaders(fo);
}

// Lỗi chưa bắt: log đầy đủ ra file, trả ProblemDetails 500 (không lộ stack).
app.UseExceptionHandler();
app.UseStatusCodePages();
if (!app.Environment.IsDevelopment()) app.UseHsts(); // HTTPS bắt buộc ngoài môi trường dev

// Swagger bật cả khi chạy thật (giai đoạn phát triển, để test trên MyASP.net). Tắt lại ở Đợt 4.
app.UseSwagger();
app.UseSwaggerUI();

app.UseHttpsRedirection();
app.UseMiddleware<PlatformMiddleware>(maxBodyBytes); // /api/v1/* -> /api/*, X-Api-Version, trần body (trước định tuyến)
app.UseRouting();
if (corsOrigins.Length > 0) app.UseCors();
app.UseAuthentication();
app.UseRateLimiter(); // sau xác thực để chia trần theo máy con (claim "sub")
app.UseAuthorization();
app.MapControllers();

app.Run();

// API-15: để SafeFamily.Api.Tests dùng WebApplicationFactory<Program>.
public partial class Program;
