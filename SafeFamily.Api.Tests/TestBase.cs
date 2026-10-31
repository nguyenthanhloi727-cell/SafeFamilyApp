using System.Net;
using Xunit;

namespace SafeFamily.Api.Tests;

[Collection("api")]
public abstract class TestBase(SharedApi shared)
{
    protected Api Api { get; } = new(shared.Factory);
    protected ApiFactory Factory => shared.Factory;

    protected static async Task Expect(HttpStatusCode code, Task<HttpResponseMessage> call, string? what = null)
    {
        var r = await call;
        if (r.StatusCode != code)
            Assert.Fail($"{what ?? "Yêu cầu"}: mong {(int)code} {code}, nhận {(int)r.StatusCode} {r.StatusCode}. Body: {await r.Content.ReadAsStringAsync()}");
    }

    protected static string Pad(int length, char c = 'a') => new(c, length);
}
