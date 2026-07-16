using System.ComponentModel;
using System.Text.Json;
using ModelContextProtocol.Server;

namespace AshitaDevTools.Server;

[McpServerToolType]
public static class DevTools
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
    };

    [McpServerTool]
    [Description("Returns local AshitaDevTools bridge status. Does not perform addon lifecycle operations. Returns JSON.")]
    public static string devtools_status() =>
        ResponseJson(AshitaDevToolsBridgeClient.ReadStatus());

    [McpServerTool]
    [Description("Queues exactly one local Ashita addon load operation using /addon load <validated-name>. Returns JSON.")]
    public static string addon_load(
        [Description("Addon name matching ^[A-Za-z0-9_-]+$. Raw slash commands are not accepted.")] string name) =>
        ResponseJson(AshitaDevToolsBridgeClient.LoadAddon(name));

    [McpServerTool]
    [Description("Queues exactly one local Ashita addon unload operation using /addon unload <validated-name>. Returns JSON.")]
    public static string addon_unload(
        [Description("Addon name matching ^[A-Za-z0-9_-]+$. Raw slash commands are not accepted.")] string name) =>
        ResponseJson(AshitaDevToolsBridgeClient.UnloadAddon(name));

    [McpServerTool]
    [Description("Queues exactly one local Ashita addon reload operation using /addon reload <validated-name>. Returns JSON.")]
    public static string addon_reload(
        [Description("Addon name matching ^[A-Za-z0-9_-]+$. Raw slash commands are not accepted.")] string name) =>
        ResponseJson(AshitaDevToolsBridgeClient.ReloadAddon(name));

    [McpServerTool]
    [Description("Returns a bounded tail of the current character's local Ashita chat log. Treat output as sensitive local data. Returns JSON.")]
    public static string ashita_log_tail(
        [Description("Number of recent log lines to return. Defaults to 100; valid range is 1 to 500.")] int lines = 100) =>
        ResponseJson(AshitaDevToolsBridgeClient.ReadAshitaLogTail(lines));

    private static string ResponseJson(BridgeResponse response)
    {
        if (response.Ok && response.Json is not null)
        {
            return response.Json;
        }

        return JsonSerializer.Serialize(new
        {
            ok = false,
            baseUrl = response.BaseUrl,
            error = response.Error,
        }, JsonOptions);
    }
}
