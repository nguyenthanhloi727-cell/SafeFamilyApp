using System.Net;
using Microsoft.AspNetCore.Mvc.ApiExplorer;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace SafeFamily.Api.Tests;

/// <summary>Mọi endpoint của controller phải hiện trong Swagger (không action nào bị ẩn / lọt khỏi tài liệu).</summary>
public class SwaggerTests(SharedApi shared) : TestBase(shared)
{
    [Fact]
    public async Task EveryControllerAction_IsInSwagger()
    {
        var r = await Api.Get("/swagger/v1/swagger.json");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var doc = await Api.Json(r);
        var documented = new HashSet<string>();
        foreach (var path in doc.GetProperty("paths").EnumerateObject())
            foreach (var op in path.Value.EnumerateObject())
                documented.Add($"{op.Name.ToUpperInvariant()} /{path.Name.TrimStart('/')}");

        var provider = Factory.Services.GetRequiredService<IApiDescriptionGroupCollectionProvider>();
        var actions = provider.ApiDescriptionGroups.Items.SelectMany(g => g.Items)
            .Select(d => $"{d.HttpMethod} /{d.RelativePath!.TrimStart('/')}")
            .ToList();

        Assert.True(actions.Count >= 40, $"Chỉ thấy {actions.Count} action; cập nhật ngưỡng nếu bớt endpoint có chủ đích.");
        var missing = actions.Where(a => !documented.Contains(a)).ToList();
        Assert.True(missing.Count == 0, "Thiếu trong Swagger: " + string.Join(", ", missing));
    }

    [Fact]
    public async Task Swagger_DeclaresBearerAuth_AndUiIsServed()
    {
        var doc = await Api.Json(await Api.Get("/swagger/v1/swagger.json"));
        Assert.True(doc.GetProperty("components").GetProperty("securitySchemes").TryGetProperty("Bearer", out _));
        await Expect(HttpStatusCode.OK, Api.Get("/swagger/index.html"));
    }
}
