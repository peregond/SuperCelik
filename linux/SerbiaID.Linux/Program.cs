using Avalonia;

namespace SerbiaID;

/// Command line (for testing; the app itself needs no arguments):
///   --selftest                 PII-free report of a real card to selftest.txt, no window
///   --demo [tab] [--dark] [--state noreader|nocard|ready|busy|error] [--problem]   fictional data, no reader needed
///   --shot file.png            with --demo: save the window as a PNG and quit
///   --pdf file.pdf             with --demo: save the printout as PDF and quit
public sealed class Options
{
    public bool Demo, Dark, Problem;
    public int Tab;
    public string State, Shot, Pdf;
}

internal static class Program
{
    public static Options Opts = new();

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Contains("--selftest"))
        {
            SelfTest.Run(Path.Combine(AppContext.BaseDirectory, "selftest.txt"));
            return 0;
        }
        string Arg(string name) { var i = Array.IndexOf(args, name); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }
        var di = Array.IndexOf(args, "--demo");
        Opts = new Options
        {
            Demo = di >= 0 || Arg("--shot") != null || Arg("--pdf") != null,
            Dark = args.Contains("--dark"), Problem = args.Contains("--problem"),
            State = Arg("--state"), Shot = Arg("--shot"), Pdf = Arg("--pdf"),
            Tab = di >= 0 && di + 1 < args.Length && int.TryParse(args[di + 1], out var t) ? t : 0,
        };
        return BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<App>().UsePlatformDetect().WithInterFont().LogToTrace();
}
