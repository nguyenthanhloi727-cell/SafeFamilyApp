using Microsoft.AspNetCore.Mvc;
using SafeFamily.Api.Data;

namespace SafeFamily.Api.Controllers;

public abstract class ApiBase : ControllerBase
{
    /// <summary>Id trong token (mẹ hoặc máy con tùy vai trò).</summary>
    protected int SubjectId => int.Parse(User.FindFirst("sub")!.Value);
    protected int FamilyId => int.Parse(User.FindFirst("fam")!.Value);
}
