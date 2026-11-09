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
        new MainWindow().Show();
    }
}
