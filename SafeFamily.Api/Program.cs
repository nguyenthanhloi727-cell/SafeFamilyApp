using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;
using SafeFamily.Api.Data;
using SafeFamily.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// Bí mật (chuỗi kết nối, khóa JWT) KHÔNG nằm trong git: đặt qua appsettings.Local.json
// (đã .gitignore), biến môi trường (ConnectionStrings__Default, Jwt__Key) hoặc cấu hình server.
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: false);

var connection = builder.Configuration.GetConnectionString("Default");
var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
if (string.IsNullOrWhiteSpace(connection))
    throw new InvalidOperationException("Thiếu ConnectionStrings:Default (xem docs/API_TIEN_TRINH.md, mục Cấu hình).");
if (jwt.Key.Length < 32)
    throw new InvalidOperationException("Jwt:Key phải dài từ 32 ký tự (xem docs/API_TIEN_TRINH.md, mục Cấu hình).");

builder.Services.AddDbContext<AppDb>(o => o.UseSqlServer(connection));
builder.Services.AddSingleton(jwt);
builder.Services.AddSingleton<TokenService>();
builder.Services.AddControllers();
builder.Services.AddHostedService<OfflineAlertService>(); // API-10: cảnh báo mẹ khi máy con mất kết nối

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
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Key)),
            RoleClaimType = System.Security.Claims.ClaimTypes.Role,
            ClockSkew = TimeSpan.FromMinutes(1),
        };
    });
builder.Services.AddAuthorization();

// Giới hạn tần suất theo IP: đăng nhập/đăng ký, và nhập mã ghép đôi (mã chỉ 6 số nên chặn đoán mò).
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy("auth", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "?",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
    o.AddPolicy("claim", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "?",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 5, Window = TimeSpan.FromMinutes(10) }));
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

// Swagger bật cả khi chạy thật (giai đoạn phát triển, để test trên MonsterASP). Tắt lại ở Đợt 4.
app.UseSwagger();
app.UseSwaggerUI();

app.UseHttpsRedirection();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
