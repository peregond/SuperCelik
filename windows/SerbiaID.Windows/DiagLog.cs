using System.Text;

namespace SerbiaID;

/// What "Copy logs and errors" in Settings puts on the clipboard: the technical side of what went wrong (error codes and
/// messages of the card and the system) with the time, the program version and the system. It is kept in memory only
/// (since the program started), and it holds no personal data from the card: errors are written without it.
internal static class DiagLog
{
    private const int Max = 200;
    private static readonly object Gate = new object();
    private static readonly List<string> Lines = new List<string>();

    public static void Add(string text)
    {
        lock (Gate)
        {
            Lines.Add(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + text);
            if (Lines.Count > Max) Lines.RemoveRange(0, Lines.Count - Max);
        }
    }

    public static void Error(Exception ex, string where = null)
    {
        var sb = new StringBuilder("ERROR ");
        if (where != null) sb.Append(where).Append(": ");
        sb.Append(ex.GetType().Name).Append(": ").Append(ex.Message);
        var inner = ex.InnerException;
        while (inner != null) { sb.Append(" <- ").Append(inner.GetType().Name).Append(": ").Append(inner.Message); inner = inner.InnerException; }
        Add(sb.ToString());
    }

    /// `state`: what the window knows (readers, card present, ...), written by the caller.
    public static string Report(string version, string state)
    {
        var sb = new StringBuilder();
        sb.AppendLine("Super Čelik " + version);
        sb.AppendLine("System: " + Environment.OSVersion + (Environment.Is64BitOperatingSystem ? " (64-bit)" : " (32-bit)"));
        sb.AppendLine("Language: " + Loc.Current);
        if (!string.IsNullOrEmpty(state)) sb.AppendLine(state);
        sb.AppendLine("Time: " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        sb.AppendLine();
        lock (Gate)
        {
            if (Lines.Count == 0) sb.AppendLine("(no errors since the program started)");
            foreach (var l in Lines) sb.AppendLine(l);
        }
        return sb.ToString();
    }
}
