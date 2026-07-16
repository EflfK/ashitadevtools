using System.Text.RegularExpressions;

namespace AshitaDevTools.Server;

public static partial class AshitaDevToolsBridgeClient
{
    private const string DefaultBaseUrl = "http://127.0.0.1:19772";
    private const int MaxLogTailLines = 500;
    internal const string ManualLoadCommand = "/addon load ashitadevtools";
    internal const string ManualStatusCommand = "/adt status";

    private static readonly HttpClient Http = new()
    {
        Timeout = TimeSpan.FromSeconds(3),
    };

    public static BridgeResponse ReadStatus() =>
        SendRead("/status", "status");

    public static BridgeResponse LoadAddon(string name) =>
        SendLifecycleOperation(AddonLifecycleOperation.Load, name);

    public static BridgeResponse UnloadAddon(string name) =>
        SendLifecycleOperation(AddonLifecycleOperation.Unload, name);

    public static BridgeResponse ReloadAddon(string name) =>
        SendLifecycleOperation(AddonLifecycleOperation.Reload, name);

    public static BridgeResponse ReadAshitaLogTail(int lines)
    {
        if (lines is < 1 or > MaxLogTailLines)
        {
            return BridgeResponse.Failure(GetConfiguredBaseUrl(), $"lines must be between 1 and {MaxLogTailLines}.");
        }

        return SendRead($"/ashita-log-tail?lines={lines}", "Ashita log tail");
    }

    private static BridgeResponse SendLifecycleOperation(AddonLifecycleOperation operation, string name)
    {
        var validation = ValidateAddonName(name);
        if (validation.Error is not null)
        {
            return BridgeResponse.Failure(GetConfiguredBaseUrl(), validation.Error);
        }

        var baseUri = GetLoopbackBaseUri();
        if (baseUri.Error is not null || baseUri.Uri is null)
        {
            return BridgeResponse.Failure(GetConfiguredBaseUrl(), baseUri.Error ?? "Invalid base URL.");
        }

        var operationName = OperationName(operation);
        var endpoint = $"/addon/{operationName}?name={Uri.EscapeDataString(validation.Name!)}";

        try
        {
            using var response = Http.PostAsync(new Uri(baseUri.Uri, endpoint), new StringContent(string.Empty))
                .GetAwaiter()
                .GetResult();
            var body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();

            if (!response.IsSuccessStatusCode)
            {
                return BridgeResponse.Failure(
                    baseUri.Uri.ToString().TrimEnd('/'),
                    $"AshitaDevTools rejected addon {operationName}: HTTP {(int)response.StatusCode}. {body}");
            }

            return BridgeResponse.Success(baseUri.Uri.ToString().TrimEnd('/'), body);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            return BridgeResponse.BridgeUnavailable(
                baseUri.Uri.ToString().TrimEnd('/'),
                $"Could not reach AshitaDevTools at {baseUri.Uri}{endpoint}. The AshitaDevTools addon may not be loaded in game. Manual load command: {ManualLoadCommand}. {ex.Message}");
        }
    }

    private static BridgeResponse SendRead(string endpoint, string label)
    {
        var baseUri = GetLoopbackBaseUri();
        if (baseUri.Error is not null || baseUri.Uri is null)
        {
            return BridgeResponse.Failure(GetConfiguredBaseUrl(), baseUri.Error ?? "Invalid base URL.");
        }

        try
        {
            var body = Http.GetStringAsync(new Uri(baseUri.Uri, endpoint)).GetAwaiter().GetResult();
            return BridgeResponse.Success(baseUri.Uri.ToString().TrimEnd('/'), body);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            return BridgeResponse.BridgeUnavailable(
                baseUri.Uri.ToString().TrimEnd('/'),
                $"Could not read {label} from AshitaDevTools at {baseUri.Uri}{endpoint}. The AshitaDevTools addon may not be loaded in game. Manual load command: {ManualLoadCommand}. {ex.Message}");
        }
    }

    private static (Uri? Uri, string? Error) GetLoopbackBaseUri()
    {
        var configured = GetConfiguredBaseUrl();

        if (!Uri.TryCreate(configured.TrimEnd('/') + "/", UriKind.Absolute, out var uri))
        {
            return (null, $"ASHITADEVTOOLS_BASE_URL is not a valid absolute URL: {configured}");
        }

        if (uri.Scheme != Uri.UriSchemeHttp)
        {
            return (null, "ASHITADEVTOOLS_BASE_URL must use http.");
        }

        if (uri.Host != "127.0.0.1")
        {
            return (null, "ASHITADEVTOOLS_BASE_URL must point to 127.0.0.1.");
        }

        if (!string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
        {
            return (null, "ASHITADEVTOOLS_BASE_URL must not include a query string or fragment.");
        }

        return (uri, null);
    }

    private static string GetConfiguredBaseUrl()
    {
        var configured = Environment.GetEnvironmentVariable("ASHITADEVTOOLS_BASE_URL");
        return string.IsNullOrWhiteSpace(configured)
            ? DefaultBaseUrl
            : configured.Trim();
    }

    private static (string? Name, string? Error) ValidateAddonName(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return (null, "Addon name is required.");
        }

        var trimmed = name.Trim();
        if (trimmed.Length > 64)
        {
            return (null, "Addon name is too long.");
        }

        if (!AddonNamePattern().IsMatch(trimmed))
        {
            return (null, "Addon name must match ^[A-Za-z0-9_-]+$.");
        }

        return (trimmed, null);
    }

    private static string OperationName(AddonLifecycleOperation operation) =>
        operation switch
        {
            AddonLifecycleOperation.Load => "load",
            AddonLifecycleOperation.Unload => "unload",
            AddonLifecycleOperation.Reload => "reload",
            _ => throw new ArgumentOutOfRangeException(nameof(operation), operation, "Unsupported addon lifecycle operation."),
        };

    [GeneratedRegex("^[A-Za-z0-9_-]+$")]
    private static partial Regex AddonNamePattern();

    private enum AddonLifecycleOperation
    {
        Load,
        Unload,
        Reload,
    }
}

public sealed record BridgeResponse(
    bool Ok,
    string BaseUrl,
    string? Json,
    string? Error,
    string? ErrorKind = null,
    string? ManualLoadCommand = null,
    string? ManualStatusCommand = null,
    string? RecoveryHint = null)
{
    public static BridgeResponse Success(string baseUrl, string json) =>
        new(true, baseUrl, json, null);

    public static BridgeResponse Failure(string baseUrl, string error) =>
        new(false, baseUrl, null, error);

    public static BridgeResponse BridgeUnavailable(string baseUrl, string error) =>
        new(
            false,
            baseUrl,
            null,
            error,
            "bridge_unreachable",
            AshitaDevToolsBridgeClient.ManualLoadCommand,
            AshitaDevToolsBridgeClient.ManualStatusCommand,
            $"Run {AshitaDevToolsBridgeClient.ManualLoadCommand} in the Ashita in-game chat, then retry the MCP tool. If it is already loaded, run {AshitaDevToolsBridgeClient.ManualStatusCommand} in game to inspect the local listener.");
}
