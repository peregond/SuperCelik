namespace SerbiaID;

/// Firefox on Windows takes client certificates from the Windows certificate store, the same place Chrome and Edge use and where the card
/// minidriver (DriverSetup.cs) makes the card certificate appear, so Firefox needs no module of its own: since version 90 it does that by
/// default. This looks at the Firefox profiles for the one case where it does not (the preference turned off) and turns it on, when the
/// user agrees. Nothing else in Firefox is touched.
internal static class FirefoxSetup
{
    private static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Mozilla", "Firefox");

    internal sealed class Status
    {
        public int Profiles;                                                            // 0 = no Firefox profile here (not installed, or never started)
        public readonly List<FirefoxProfile> Disabled = new List<FirefoxProfile>();     // the preference is off in these: it can be turned on
        public int OldMajor;                                                            // every profile is older than Firefox 75, which cannot use system certificates at all: the newest version seen (0 = no such case)
    }

    public static Status Check()
    {
        var st = new Status();
        try
        {
            int tooOld = 0, newest = 0;
            foreach (var p in FirefoxProfiles.Find(Root))
            {
                st.Profiles++;
                var state = FirefoxProfiles.CheckOsCerts(p);
                if (state == OsCertsState.Disabled) st.Disabled.Add(p);
                else if (state == OsCertsState.TooOld) { tooOld++; if (p.Major > newest) newest = p.Major; }
            }
            // an old profile next to a current one is just an abandoned profile: only report it when nothing else is left
            if (tooOld > 0 && tooOld == st.Profiles) st.OldMajor = newest;
        }
        catch { /* unreadable profile folder: say nothing */ }
        return st;
    }

    /// Turns the preference on where it is off. Returns how many profiles were changed.
    public static int Enable(Status st) => FirefoxProfiles.EnableOsCerts(st.Disabled).Count;
}
