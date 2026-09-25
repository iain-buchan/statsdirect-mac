using System.Net;
using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;

var builder = WebApplication.CreateBuilder(args);
// A reverse proxy must terminate public HTTPS. No HTTP endpoint is intended for public use.
if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("ASPNETCORE_URLS"))) builder.WebHost.UseUrls("http://127.0.0.1:8787");
builder.WebHost.ConfigureKestrel(o => o.Limits.MaxRequestBodySize = 500_000);
builder.Logging.ClearProviders(); builder.Logging.AddSimpleConsole(); builder.Logging.SetMinimumLevel(LogLevel.Warning);
var settings = new ServiceSettings(builder.Environment.IsDevelopment());
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.KnownProxies.Clear(); o.KnownIPNetworks.Clear(); o.ForwardLimit = 1;
    // Trust only explicit ingress addresses. Never trust arbitrary X-Forwarded-For values.
    foreach (var ip in (Environment.GetEnvironmentVariable("TUTOR_TRUSTED_PROXIES") ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries)) o.KnownProxies.Add(IPAddress.Parse(ip.Trim()));
});
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = 429;
    o.AddFixedWindowLimiter("global", limit => { limit.PermitLimit = 120; limit.Window = TimeSpan.FromMinutes(1); limit.QueueLimit = 0; });
    o.OnRejected = async (context, cancellation) =>
        await context.HttpContext.Response.WriteAsJsonAsync(new { error = new { code = "rate_limit", message = "The tutor is busy. Please wait a moment and try again." } }, cancellation);
});
builder.Services.AddSingleton(settings);
builder.Services.AddSingleton<SessionLedger>();
builder.Services.AddSingleton<TutorProxy>();
var app = builder.Build();
// With no configured proxies do not enable forwarding: clearing both lists would trust everyone.
if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("TUTOR_TRUSTED_PROXIES"))) app.UseForwardedHeaders();
app.Use(async (context, next) =>
{
    context.Response.Headers.CacheControl = "no-store";
    context.Response.Headers.XContentTypeOptions = "nosniff";
    try
    {
        if (!context.Request.IsHttps && !(settings.Development && context.Connection.RemoteIpAddress is { } ip && IPAddress.IsLoopback(ip)))
            throw new TutorFailure(400, "https_required", "The learning service requires HTTPS.");
        if (!string.IsNullOrEmpty(context.Request.Headers.Origin)) throw new TutorFailure(403, "native_only", "Use the StatsDirect application to connect.");
        if (context.Request.Path != "/health" && string.IsNullOrWhiteSpace(settings.APIKey)) throw new TutorFailure(503, "not_activated", "The shared tutor has not been activated by its administrator yet. No personal OpenAI key is needed.");
        await next(context);
    }
    catch (TutorFailure error)
    {
        context.Response.StatusCode = error.Status;
        await context.Response.WriteAsJsonAsync(new { error = new { code = error.Code, message = error.Message } });
    }
    catch (Exception error) when (error is JsonException or BadHttpRequestException)
    {
        context.Response.StatusCode = error is BadHttpRequestException bad ? bad.StatusCode : 400;
        await context.Response.WriteAsJsonAsync(new { error = new { code = "invalid_request", message = "The learning request could not be read." } });
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
    catch (Exception)
    {
        // Do not log request bodies, bearer tokens, provider bodies or exception details.
        context.Response.StatusCode = 503;
        await context.Response.WriteAsJsonAsync(new { error = new { code = "unavailable", message = "The shared tutor is temporarily unavailable. Please try again later." } });
    }
});
app.UseRateLimiter();
app.MapGet("/health", () => Results.Json(new { service = "StatsDirect Learning", protocol = 1, activated = !string.IsNullOrWhiteSpace(settings.APIKey) })).RequireRateLimiting("global");
app.MapPost("/v1/sessions", (HttpContext context, SessionLedger ledger) =>
{
    var session = ledger.Create(Peer(context));
    return Results.Json(new { schemaVersion = 1, token = session.Token, expiresAt = session.ExpiresAt.ToString("O") });
}).RequireRateLimiting("global");
app.MapDelete("/v1/session", (HttpContext context, SessionLedger ledger) => { ledger.Revoke(Token(context)); return Results.NoContent(); }).RequireRateLimiting("global");
app.MapPost("/v1/tutor", async (HttpContext context, SessionLedger ledger, TutorProxy tutor) =>
{
    var token = Token(context);
    var body = await context.Request.ReadFromJsonAsync<TutorRequest>(context.RequestAborted) ?? throw new TutorFailure(400, "invalid_request", "Enter a learning question.");
    tutor.Validate(body);
    var reservation = ledger.Reserve(token, Peer(context));
    try { return Results.Json(await tutor.Reply(body, context.RequestAborted)); }
    finally { ledger.Release(reservation); }
}).RequireRateLimiting("global");
// Validate the store and trusted teaching material at startup, including single-instance lock.
_ = app.Services.GetRequiredService<SessionLedger>();
_ = app.Services.GetRequiredService<TutorProxy>();
app.Run();

static string Peer(HttpContext context) => context.Connection.RemoteIpAddress?.MapToIPv6().ToString() ?? "unknown";
static string Token(HttpContext context)
{
    var value = context.Request.Headers.Authorization.ToString();
    if (!value.StartsWith("Bearer ", StringComparison.Ordinal) || value.Length != 71 || value[7..].Any(c => !Uri.IsHexDigit(c)))
        throw new TutorFailure(401, "session_expired", "Your learning connection has expired. Send again to reconnect.");
    return value[7..];
}
