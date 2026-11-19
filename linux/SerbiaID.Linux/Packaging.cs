namespace SerbiaID;

/// How the app was installed: as an AppImage (the AppImage runtime sets $APPIMAGE) or inside a Flatpak sandbox.
public static class Packaging
{
    public static bool IsAppImage => !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APPIMAGE"));
    public static bool IsFlatpak => File.Exists("/.flatpak-info");
}
