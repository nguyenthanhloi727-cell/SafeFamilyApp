using System.Text.Json;

namespace SafeFamily.Api.Services;

/// <summary>
/// Quy tắc yêu cầu của máy con (API-06): loại cho phép, kiểm payload, và lệnh sinh ra khi mẹ quyết định.
/// Chỉ nhận loại yêu cầu và số phút xin: payload có trường thừa bị từ chối để không lọt nội dung/app đang dùng.
/// </summary>
public static class RequestRules
{
    public const string ExtraTime = "extra_time";
    public const string StudyDone = "study_done";
    public const string Pending = "pending";
    public const string Approved = "approved";
    public const string Rejected = "rejected";

    public const int MaxPayloadBytes = 256;
    /// <summary>Số phút con được xin (khớp TimeLimits.MAX_BONUS_MINUTES ở máy con có dư).</summary>
    public const int MaxRequestMinutes = 240;
    /// <summary>Số yêu cầu tối đa lưu cho một máy: đủ xem lịch sử, chặn máy con làm đầy bảng.</summary>
    public const int MaxRowsPerDevice = 200;
    /// <summary>Yêu cầu đã quyết định giữ bấy nhiêu ngày rồi dọn khi máy con gửi yêu cầu mới.</summary>
    public static readonly TimeSpan DecidedRetention = TimeSpan.FromDays(7);
    /// <summary>Yêu cầu chờ quá lâu thì coi là hết hạn: không hiện cho mẹ, không duyệt được, con được gửi lại.</summary>
    public static readonly TimeSpan PendingMaxAge = CommandRules.MaxAge;

    public static bool IsStatus(string? s) => s is Pending or Approved or Rejected;

    /// <summary>Trả về lỗi hoặc null. <paramref name="canonical"/> là payload chuẩn hóa để lưu.</summary>
    public static string? Validate(string kind, string? payloadJson, out string canonical)
    {
        canonical = "{}";
        if (kind is not (ExtraTime or StudyDone)) return "Loại yêu cầu không hợp lệ.";
        var raw = string.IsNullOrWhiteSpace(payloadJson) ? "{}" : payloadJson;
        if (System.Text.Encoding.UTF8.GetByteCount(raw) > MaxPayloadBytes) return "Payload quá lớn.";
        JsonElement root;
        try
        {
            using var doc = JsonDocument.Parse(raw);
            root = doc.RootElement.Clone();
        }
        catch (JsonException) { return "Payload không phải JSON hợp lệ."; }
        if (root.ValueKind != JsonValueKind.Object) return "Payload phải là một đối tượng JSON.";
        var props = root.EnumerateObject().ToList();
        if (kind == StudyDone)
            return props.Count == 0 ? null : "study_done không có trường nào.";
        if (props.Count != 1 || props[0].Name != "minutes") return "extra_time chỉ có trường minutes.";
        var m = props[0].Value;
        if (m.ValueKind != JsonValueKind.Number || !m.TryGetInt32(out var minutes)) return "minutes phải là số nguyên.";
        if (minutes is < 1 or > MaxRequestMinutes) return $"minutes phải từ 1 đến {MaxRequestMinutes}.";
        canonical = JsonSerializer.Serialize(new { minutes });
        return null;
    }

    public static int RequestedMinutes(string payload)
    {
        try
        {
            using var doc = JsonDocument.Parse(payload);
            return doc.RootElement.TryGetProperty("minutes", out var m) && m.TryGetInt32(out var v) ? v : 0;
        }
        catch (JsonException) { return 0; }
    }

    /// <summary>
    /// Lệnh server tự tạo khi mẹ quyết định (tái dùng <see cref="CommandRules"/>), hoặc null nếu không cần lệnh
    /// (từ chối xin thêm giờ: con xem kết quả qua GET me/requests/{id}).
    /// </summary>
    public static (string Type, string Payload)? CommandFor(string kind, bool approved, int minutes) => (kind, approved) switch
    {
        (StudyDone, true) => ("study_approve", "{}"),
        (StudyDone, false) => ("study_reject", "{}"),
        (ExtraTime, true) => (CommandRules.ExtraTimeGrant, JsonSerializer.Serialize(new { minutes })),
        _ => null,
    };
}
