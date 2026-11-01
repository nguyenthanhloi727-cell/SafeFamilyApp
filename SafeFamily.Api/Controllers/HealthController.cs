using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SafeFamily.Api.Data;
using SafeFamily.Api.Services;

namespace SafeFamily.Api.Controllers;

[ApiController]
[Route("health")]
[AllowAnonymous]
public class HealthController(AppDb db, ILogger<HealthController> log) : ControllerBase
{
    /// <summary>
    /// Kiểm tra sống cho MyASP.net / giám sát bên ngoài. Không cần token, không lộ dữ liệu.
    /// 200 khi API chạy và nối được CSDL; 503 khi CSDL không nối được.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Get()
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(HttpContext.RequestAborted);
            cts.CancelAfter(TimeSpan.FromSeconds(5));
            if (await db.Database.CanConnectAsync(cts.Token))
                return Ok(new { status = "ok", apiVersion = PlatformRules.ApiVersion, time = DateTime.UtcNow });
        }
        catch (Exception e) when (e is not OperationCanceledException || !HttpContext.RequestAborted.IsCancellationRequested)
        {
            log.LogError(e, "Health: không nối được CSDL.");
        }
        return StatusCode(StatusCodes.Status503ServiceUnavailable,
            new { status = "database_unavailable", apiVersion = PlatformRules.ApiVersion, time = DateTime.UtcNow });
    }
}
