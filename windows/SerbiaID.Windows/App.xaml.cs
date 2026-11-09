using System.Windows;

namespace SerbiaID;

public partial class App : Application
{
    private void OnStartup(object sender, StartupEventArgs e)
    {
        // `SerbiaID.exe --selftest` writes a PII-free report to selftest.txt and exits (no window).
        if (e.Args.Contains("--selftest"))
        {
            SelfTest.Run(Path.Combine(AppContext.BaseDirectory, "selftest.txt"));
            Shutdown();
            return;
        }
        // `--updatetest` checks GitHub and downloads+verifies the installer (does NOT run it); writes updatetest.txt
        if (e.Args.Contains("--updatetest"))
        {
            var o = Path.Combine(AppContext.BaseDirectory, "updatetest.txt");
            try
            {
                var (info, reachable) = Task.Run(() => Updater.CheckAsync()).GetAwaiter().GetResult();
                var s = $"current={Updater.CurrentText} reachable={reachable} found={(info == null ? "none" : info.Version.ToString(3))}";
                if (info != null)
                {
                    var p = Task.Run(() => Updater.DownloadAsync(info)).GetAwaiter().GetResult();
                    s += $"\ndownloaded={new FileInfo(p).Length} bytes, sha256 published={(info.Sha256.Length > 0)} (verified when present)";
                }
                File.WriteAllText(o, s);
            }
            catch (Exception ex) { File.WriteAllText(o, "ERROR " + ex.Message); }
            Shutdown(); return;
        }
        // `--shot file.png [tab]` renders the window with FICTIONAL demo data to a PNG (for UI review).
        var si = Array.IndexOf(e.Args, "--shot");
        if (si >= 0 && si + 1 < e.Args.Length)
        {
            var w = new MainWindow();
            w.LoadDemo(e.Args.Length > si + 2 ? int.Parse(e.Args[si + 2]) : 0, e.Args.Contains("--dark"), e.Args.Contains("--problem"));
            w.Show();
            Dispatcher.InvokeAsync(() => { w.SaveScreenshot(e.Args[si + 1]); Shutdown(); }, System.Windows.Threading.DispatcherPriority.ContextIdle);
            return;
        }
        var pi = Array.IndexOf(e.Args, "--pdf");     // demo-data PDF export (for testing)
        if (pi >= 0 && pi + 1 < e.Args.Length)
        {
            var w = new MainWindow(); w.LoadDemo(0, false, false);
            w.ExportDemoPdf(e.Args[pi + 1]); Shutdown(); return;
        }
        new MainWindow().Show();
    }
}
