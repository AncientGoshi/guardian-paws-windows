using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;

internal sealed class Config
{
    public int Version { get; set; } = 2;
    public string ChildUserName { get; set; } = "";
    public string ChildSid { get; set; } = "";
    public string BotTokenProtected { get; set; } = "";
    public string MiniAppUrl { get; set; } = "https://guard.catbiologymc.com/guardian";
    public string ExtensionUpdateUrl { get; set; } = "";
    public List<long> GuardianIds { get; set; } = [];
    public Pairing Pairing { get; set; } = new();
    public long? LastUpdateId { get; set; }
    public bool ShortsBlocked { get; set; }
}
internal sealed class Pairing { public string Code { get; set; } = ""; public DateTime ExpiresUtc { get; set; } }

internal static class Program
{
    private const string ExtensionId = "llkmcggfkabiooejicbdngjaagobgaen";
    private static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GuardianPaws");
    private static readonly string App = Path.Combine(Root, "app");
    private static readonly string ConfigPath = Path.Combine(Root, "config.json");
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };

    static async Task<int> Main(string[] args)
    {
        try
        {
            if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("Guardian Paws runs only on Windows.");
            var mode = args.FirstOrDefault()?.ToLowerInvariant() ?? "";
            return mode switch
            {
                "install" => Install(ParseOptions(args.Skip(1))),
                "bot" => await BotLoop(),
                "enforcer" => Enforce(),
                "uninstall" => Uninstall(),
                _ => Usage()
            };
        }
        catch (Exception ex) { Console.Error.WriteLine("Guardian Paws: " + ex.Message); return 1; }
    }

    static int Usage() { Console.Error.WriteLine("Usage: GuardianPaws.exe install --child NAME --display NAME --extension-update-url HTTPS_URL"); return 2; }
    static Dictionary<string,string> ParseOptions(IEnumerable<string> args)
    {
        var result = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase); var all = args.ToArray();
        for (var i = 0; i < all.Length; i++) if (all[i].StartsWith("--") && i + 1 < all.Length) result[all[i][2..]] = all[++i];
        return result;
    }
    static void RequireAdmin()
    {
        using var id = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator)) throw new InvalidOperationException("Run Install-GuardianPaws.cmd with Run as administrator.");
    }
    static int Install(Dictionary<string,string> options)
    {
        RequireAdmin();
        if (!options.TryGetValue("child", out var child) || !System.Text.RegularExpressions.Regex.IsMatch(child, "^[A-Za-z0-9._-]{1,20}$")) throw new InvalidOperationException("--child must be a new 1–20 character name containing only letters, numbers, dot, underscore, or hyphen.");
        if (!options.TryGetValue("display", out var display) || display.Length is < 1 or > 64) throw new InvalidOperationException("--display is required (1–64 characters).");
        if (!options.TryGetValue("extension-update-url", out var updateUrl) || !Uri.TryCreate(updateUrl, UriKind.Absolute, out var updateUri) || updateUri.Scheme != Uri.UriSchemeHttps) throw new InvalidOperationException("--extension-update-url must be an HTTPS URL.");
        var existing = Run("net.exe", $"user \"{child}\"");
        if (existing.ExitCode == 0) throw new InvalidOperationException($"'{child}' already exists. Refusing to alter any existing account.");
        Console.Write("Paste the existing Telegram bot token: "); var token = ReadSecret();
        if (string.IsNullOrWhiteSpace(token)) throw new InvalidOperationException("No bot token was supplied.");
        Console.Write($"Create a password for the new child account {child}: "); var password = ReadSecret();
        if (string.IsNullOrWhiteSpace(password)) throw new InvalidOperationException("No child password was supplied.");
        var create = CreateChildAccount(child, password, display);
        if (create.ExitCode != 0) throw new InvalidOperationException("Windows could not create the child account: " + create.Output);
        try
        {
            Directory.CreateDirectory(App);
            var exe = Environment.ProcessPath ?? throw new InvalidOperationException("Cannot locate GuardianPaws.exe.");
            File.Copy(exe, Path.Combine(App, "GuardianPaws.exe"), true);
            var sid = LookupSid(child);
            var code = Random.Shared.Next(100_000_000, 1_000_000_000).ToString();
            SaveConfig(new Config { ChildUserName = child, ChildSid = sid, BotTokenProtected = Convert.ToBase64String(Dpapi.Protect(Encoding.UTF8.GetBytes(token))), ExtensionUpdateUrl = updateUrl, Pairing = new Pairing { Code = code, ExpiresUtc = DateTime.UtcNow.AddMinutes(15) } });
            SetChildPolicies(sid, updateUrl, false);
            var account = Environment.MachineName + "\\" + child;
            MustRun("icacls.exe", $"\"{Root}\" /inheritance:r /grant:r \"SYSTEM:(OI)(CI)F\" \"Administrators:(OI)(CI)F\" \"{account}:(OI)(CI)RX\"");
            MustRun("icacls.exe", $"\"{ConfigPath}\" /inheritance:r /grant:r \"SYSTEM:F\" \"Administrators:F\"");
            var installedExe = Path.Combine(App, "GuardianPaws.exe");
            CreateTask("DirectBot", "ONSTART", $"\"{installedExe}\" bot", "/RU", "SYSTEM", "/RL", "HIGHEST");
            CreateTask("Enforcer", "MINUTE", $"\"{installedExe}\" enforcer", "/MO", "1", "/RU", "SYSTEM", "/RL", "HIGHEST");
            MustRun("schtasks.exe", "/Run /TN \"GuardianPaws-DirectBot\"");
            MustRun("schtasks.exe", "/Run /TN \"GuardianPaws-Enforcer\"");
            Console.WriteLine($"Installed. In a private chat with the bot, send: /pair {code}");
            Console.WriteLine("The code expires in 15 minutes and permits at most two guardian Telegram accounts.");
            Console.WriteLine("Parent-admin recovery: Task Scheduler > Task Scheduler Library > GuardianPaws-DirectBot / GuardianPaws-Enforcer, or run Install-GuardianPaws.cmd uninstall.");
            return 0;
        }
        catch
        {
            Run("net.exe", $"user \"{child}\" /delete");
            throw;
        }
    }
    static void CreateTask(string name, string schedule, string taskRun, params string[] extra)
    {
        var start = new ProcessStartInfo("schtasks.exe") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        foreach (var argument in new[] { "/Create", "/F", "/TN", $"GuardianPaws-{name}", "/SC", schedule }.Concat(extra)) start.ArgumentList.Add(argument);
        start.ArgumentList.Add("/TR");
        start.ArgumentList.Add(taskRun);
        MustRun(start);
    }
    static int Uninstall()
    {
        RequireAdmin();
        Run("schtasks.exe", "/Delete /F /TN \"GuardianPaws-DirectBot\"");
        Run("schtasks.exe", "/Delete /F /TN \"GuardianPaws-Enforcer\"");
        Console.WriteLine("Tasks removed. Delete %ProgramData%\\GuardianPaws only after you have saved any required pairing/configuration data.");
        return 0;
    }
    static string ReadSecret()
    {
        var b = new StringBuilder(); ConsoleKeyInfo k;
        while ((k = Console.ReadKey(intercept: true)).Key != ConsoleKey.Enter) { if (k.Key == ConsoleKey.Backspace && b.Length > 0) b.Length--; else if (!char.IsControl(k.KeyChar)) b.Append(k.KeyChar); }
        Console.WriteLine(); return b.ToString();
    }
    static (int ExitCode, string Output) CreateChildAccount(string child, string password, string display)
    {
        var start = new ProcessStartInfo("net.exe") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        start.ArgumentList.Add("user");
        start.ArgumentList.Add(child);
        start.ArgumentList.Add(password);
        start.ArgumentList.Add("/add");
        start.ArgumentList.Add("/expires:never");
        start.ArgumentList.Add("/fullname:" + display);
        return Run(start);
    }
    static string LookupSid(string name)
    {
        var account = new NTAccount(Environment.MachineName, name);
        return ((SecurityIdentifier)account.Translate(typeof(SecurityIdentifier))).Value;
    }
    static Config ReadConfig() => JsonSerializer.Deserialize<Config>(File.ReadAllText(ConfigPath), Json) ?? throw new InvalidOperationException("Invalid Guardian Paws configuration.");
    static void SaveConfig(Config config) { Directory.CreateDirectory(Root); var tmp = ConfigPath + ".tmp"; File.WriteAllText(tmp, JsonSerializer.Serialize(config, Json)); File.Move(tmp, ConfigPath, true); }

    static async Task<int> BotLoop()
    {
        var http = new HttpClient { Timeout = TimeSpan.FromSeconds(45) };
        while (true)
        {
            try
            {
                var c = ReadConfig(); var token = Encoding.UTF8.GetString(Dpapi.Unprotect(Convert.FromBase64String(c.BotTokenProtected)));
                await Api(http, token, "deleteWebhook", new { drop_pending_updates = false });
                while (true)
                {
                    c = ReadConfig(); var data = await GetJson(http, $"https://api.telegram.org/bot{token}/getUpdates?timeout=30&offset={(c.LastUpdateId ?? 0) + 1}");
                    foreach (var update in data.RootElement.GetProperty("result").EnumerateArray())
                    {
                        c.LastUpdateId = update.GetProperty("update_id").GetInt64();
                        if (!update.TryGetProperty("message", out var m) || !m.TryGetProperty("chat", out var chat) || chat.GetProperty("type").GetString() != "private" || !m.TryGetProperty("from", out var from)) { SaveConfig(c); continue; }
                        var sender = from.GetProperty("id").GetInt64(); var chatId = chat.GetProperty("id").GetInt64(); var text = m.TryGetProperty("text", out var t) ? (t.GetString() ?? "").Trim().ToLowerInvariant() : "";
                        var action = "";
                        if (m.TryGetProperty("web_app_data", out var webApp) && webApp.TryGetProperty("data", out var webData))
                        {
                            try { using var payload = JsonDocument.Parse(webData.GetString() ?? ""); if (payload.RootElement.TryGetProperty("v", out var version) && version.GetInt32() == 1 && payload.RootElement.TryGetProperty("action", out var requested)) action = requested.GetString() ?? ""; } catch { action = ""; }
                            if (action is not ("shorts-off" or "shorts-on" or "downtime-on" or "downtime-off" or "status")) action = "";
                        }
                        string reply = "";
                        if (text.StartsWith("/pair ") && text.Length == 15 && text[6..].All(char.IsDigit)) { if (c.Pairing.Code == text[6..] && c.Pairing.ExpiresUtc > DateTime.UtcNow && c.GuardianIds.Count < 2 && !c.GuardianIds.Contains(sender)) { c.GuardianIds.Add(sender); c.Pairing.Code = ""; reply = "This Telegram account is now paired as a Guardian."; } else reply = "Pairing was refused."; }
                        else if (!c.GuardianIds.Contains(sender)) { SaveConfig(c); continue; }
                        else if (text is "/shorts off" or "/shorts on" || action is "shorts-off" or "shorts-on") { c.ShortsBlocked = text == "/shorts off" || action == "shorts-off"; SetChildPolicies(c.ChildSid, c.ExtensionUpdateUrl, c.ShortsBlocked); reply = c.ShortsBlocked ? "YouTube Shorts are blocked in the child Edge/Chrome profile." : "YouTube Shorts are allowed in the child Edge/Chrome profile."; }
                        else if (text == "/downtime on" || action == "downtime-on") { DisableChild(c.ChildUserName); reply = "Downtime is active. The child account was disabled."; }
                        else if (text == "/downtime off" || action == "downtime-off") { EnableChild(c.ChildUserName); reply = "Downtime is off. The child account may sign in again."; }
                        else if (text is "/status" or "/shorts status" or "/downtime status" || action == "status") reply = $"Child account: {(IsEnabled(c.ChildUserName) ? "available" : "downtime active")}\nYouTube Shorts: {(c.ShortsBlocked ? "blocked" : "allowed")}";
                        else if (text is "/panel" or "/start") { await Api(http, token, "sendMessage", new { chat_id = chatId, text = "Open Guardian Paws to control this Windows child account.", reply_markup = new { keyboard = new[] { new[] { new { text = "Open Guardian Paws", web_app = new { url = c.MiniAppUrl } } } }, resize_keyboard = true, is_persistent = true } }); }
                        else if (text == "/help") reply = "/panel\n/shorts off|on|status\n/downtime on|off|status\n/status";
                        SaveConfig(c); if (!string.IsNullOrEmpty(reply)) await Api(http, token, "sendMessage", new { chat_id = chatId, text = reply });
                    }
                }
            }
            catch { await Task.Delay(TimeSpan.FromSeconds(10)); }
        }
    }
    static async Task<JsonDocument> GetJson(HttpClient h, string uri) { using var r = await h.GetAsync(uri); r.EnsureSuccessStatusCode(); return JsonDocument.Parse(await r.Content.ReadAsStringAsync()); }
    static async Task Api(HttpClient h, string token, string method, object body) { using var r = await h.PostAsync($"https://api.telegram.org/bot{token}/{method}", new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")); r.EnsureSuccessStatusCode(); }
    static int Enforce() { var c = ReadConfig(); SetChildPolicies(c.ChildSid, c.ExtensionUpdateUrl, c.ShortsBlocked); return 0; }
    static void SetChildPolicies(string sid, string updateUrl, bool shortsBlocked)
    {
        foreach (var browser in new[] { "Microsoft\\Edge", "Google\\Chrome" })
        {
            using var force = Registry.Users.CreateSubKey($"{sid}\\Software\\Policies\\{browser}\\ExtensionInstallForcelist"); force?.SetValue("GuardianPaws1", $"{ExtensionId};{updateUrl}", RegistryValueKind.String);
            using var urls = Registry.Users.CreateSubKey($"{sid}\\Software\\Policies\\{browser}\\URLBlocklist"); if (shortsBlocked) { urls?.SetValue("GuardianPaws1", "*://www.youtube.com/shorts*", RegistryValueKind.String); urls?.SetValue("GuardianPaws2", "*://youtube.com/shorts*", RegistryValueKind.String); } else { urls?.DeleteValue("GuardianPaws1", false); urls?.DeleteValue("GuardianPaws2", false); }
        }
    }
    static bool IsEnabled(string child) => Run("net.exe", $"user \"{child}\"").Output.Contains("Account active               Yes", StringComparison.OrdinalIgnoreCase);
    static void DisableChild(string child) => MustRun("net.exe", $"user \"{child}\" /active:no");
    static void EnableChild(string child) => MustRun("net.exe", $"user \"{child}\" /active:yes");
    static (int ExitCode, string Output) Run(string file, string args) { using var p = Process.Start(new ProcessStartInfo(file, args) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true })!; var o = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd(); p.WaitForExit(); return (p.ExitCode, o); }
    static (int ExitCode, string Output) Run(ProcessStartInfo start) { using var p = Process.Start(start)!; var o = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd(); p.WaitForExit(); return (p.ExitCode, o); }
    static void MustRun(string file, string args) { var r = Run(file, args); if (r.ExitCode != 0) throw new InvalidOperationException($"{file} failed: {r.Output}"); }
    static void MustRun(ProcessStartInfo start) { var r = Run(start); if (r.ExitCode != 0) throw new InvalidOperationException($"{start.FileName} failed: {r.Output}"); }
}
internal static class Dpapi
{
    [StructLayout(LayoutKind.Sequential)] private struct Blob { public int cbData; public IntPtr pbData; }
    [DllImport("crypt32.dll", SetLastError = true)] private static extern bool CryptProtectData(ref Blob input, string? description, IntPtr entropy, IntPtr reserved, IntPtr prompt, int flags, out Blob output);
    [DllImport("crypt32.dll", SetLastError = true)] private static extern bool CryptUnprotectData(ref Blob input, IntPtr description, IntPtr entropy, IntPtr reserved, IntPtr prompt, int flags, out Blob output);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr ptr);
    private const int LocalMachine = 4;
    public static byte[] Protect(byte[] value) => Transform(value, true);
    public static byte[] Unprotect(byte[] value) => Transform(value, false);
    private static byte[] Transform(byte[] value, bool protect)
    {
        var p = Marshal.AllocHGlobal(value.Length); try { Marshal.Copy(value, 0, p, value.Length); var input = new Blob { cbData = value.Length, pbData = p }; var ok = protect ? CryptProtectData(ref input, null, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, LocalMachine, out var output) : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, LocalMachine, out output); if (!ok) throw new InvalidOperationException("Windows DPAPI failed: " + Marshal.GetLastWin32Error()); try { var result = new byte[output.cbData]; Marshal.Copy(output.pbData, result, 0, result.Length); return result; } finally { LocalFree(output.pbData); } } finally { Marshal.FreeHGlobal(p); }
    }
}
