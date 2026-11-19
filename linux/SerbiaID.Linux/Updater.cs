using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SerbiaID;

/// Looks for a newer GitHub release and tells about it. It never downloads or installs anything:
/// on Linux the update is a new package / AppImage that the user takes from the release page.
public static class Updater
{
    public const string Repo = "peregond/SuperCelik";

    public static Version Current => Parse(Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion) ?? new Version(0, 0, 0);
    public static string CurrentText => Current.ToString(3);

    private static Version Parse(string s)
    {
        var m = Regex.Match(s ?? "", @"(\d+)\.(\d+)\.(\d+)");
        return m.Success ? new Version(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value)) : null;
    }

    /// Info = null when up to date; Reachable = false when the release could not be read.
    public static async Task<(Version Info, string Page, bool Reachable)> CheckAsync()
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("SuperCelik-updater");
        http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        using var resp = await http.GetAsync($"https://api.github.com/repos/{Repo}/releases/latest");
        if (!resp.IsSuccessStatusCode) return (null, null, false);
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
        var remote = Parse(doc.RootElement.GetProperty("tag_name").GetString());
        var page = $"https://github.com/{Repo}/releases/latest";
        return (remote != null && remote > Current ? remote : null, page, true);
    }
}
