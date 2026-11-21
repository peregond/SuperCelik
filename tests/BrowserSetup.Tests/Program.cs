using System.Text;
using SerbiaID;

int failures = 0;
void Check(bool ok, string what) { Console.WriteLine((ok ? "  ok   " : "  FAIL ") + what); if (!ok) failures++; }

string Temp() { var d = Path.Combine(Path.GetTempPath(), "fftest-" + Guid.NewGuid().ToString("N").Substring(0, 8)); Directory.CreateDirectory(d); return d; }
void Write(string dir, string file, string text) { Directory.CreateDirectory(dir); File.WriteAllText(Path.Combine(dir, file), text, new UTF8Encoding(false)); }
string Read(string dir, string file) => File.ReadAllText(Path.Combine(dir, file));
void Profile(string dir, string major = null) { Write(dir, "prefs.js", "// Mozilla User Preferences\n"); if (major != null) Write(dir, "compatibility.ini", "[Compatibility]\nLastVersion=" + major + ".0_20260105123456/20260105123456\n"); }
const string P = FirefoxProfiles.OsCertsPref;
string Off = "user_pref(\"" + P + "\", false);\n", On = "user_pref(\"" + P + "\", true);\n";

Console.WriteLine("reading preferences");
var d = Temp();
Check(FirefoxProfiles.ReadBoolPref(d, P) == null, "no files: not set");
Write(d, "prefs.js", "// c\n" + Off + "user_pref(\"other\", true);\n");
Check(FirefoxProfiles.ReadBoolPref(d, P) == false, "prefs.js false");
Write(d, "user.js", On);
Check(FirefoxProfiles.ReadBoolPref(d, P) == true, "user.js wins over prefs.js");
Write(d, "user.js", "user_pref(\"" + P + "\", \"yes\");\n");
Check(FirefoxProfiles.ReadBoolPref(d, P) == null, "a value that is not a boolean counts as not set");
Write(d, "prefs.js", "user_pref(\"" + P + "\", false);\r\nuser_pref(\"" + P + "\", true);\r\n"); File.Delete(Path.Combine(d, "user.js"));
Check(FirefoxProfiles.ReadBoolPref(d, P) == true, "CRLF file, the last line wins");
Write(d, "prefs.js", "user_pref(\"" + P + ".x\", false);\n");
Check(FirefoxProfiles.ReadBoolPref(d, P) == null, "a preference with a longer name is not confused with it");

Console.WriteLine("writing user.js");
d = Temp();
Check(FirefoxProfiles.SetBoolPref(d, P, true) && Read(d, "user.js").Replace("\r", "") == "user_pref(\"" + P + "\", true);\n", "creates the file");
Check(FirefoxProfiles.SetBoolPref(d, P, true) && Read(d, "user.js").Split(new[] { P }, StringSplitOptions.None).Length == 2, "idempotent: no second line");
Write(d, "user.js", "// mine\r\nuser_pref(\"a\", 1);\r\n" + Off.Replace("\n", "\r\n") + Off.Replace("\n", "\r\n") + "user_pref(\"b\", \"x\");");
Check(FirefoxProfiles.SetBoolPref(d, P, true), "rewrites an existing file");
Check(Read(d, "user.js") == "// mine\r\nuser_pref(\"a\", 1);\r\n" + On.Replace("\n", "\r\n") + "user_pref(\"b\", \"x\");\r\n", "keeps the other lines and the CRLF style, replaces and de-duplicates");
Check(!File.Exists(Path.Combine(d, "user.js.supercelik-tmp")), "no temporary file is left behind");
Write(d, "user.js", "user_pref(\"a\", 1);");
FirefoxProfiles.SetBoolPref(d, P, true);
Check(Read(d, "user.js").Replace("\r", "") == "user_pref(\"a\", 1);\nuser_pref(\"" + P + "\", true);\n", "appends after a last line without a newline");
Check(!FirefoxProfiles.SetBoolPref(Path.Combine(d, "missing", "deeper"), P, true), "a missing folder gives false, not an exception");

Console.WriteLine("system certificates (Windows, macOS)");
FirefoxProfile Prof(string major, string prefs) { var dir = Temp(); if (major != null) Write(dir, "compatibility.ini", "[Compatibility]\nLastVersion=" + major + ".0_20260105/20260105\n"); if (prefs != null) Write(dir, "prefs.js", prefs); return new FirefoxProfile { Dir = dir, Name = "x", Major = FirefoxProfiles.ReadMajor(dir) }; }
Check(FirefoxProfiles.ReadMajor(Prof("147", null).Dir) == 147, "the Firefox version is read from compatibility.ini");
Check(FirefoxProfiles.CheckOsCerts(Prof(null, null)) == OsCertsState.Ok, "unknown version, nothing set: fine");
Check(FirefoxProfiles.CheckOsCerts(Prof("147", null)) == OsCertsState.Ok, "Firefox 147, nothing set: fine (on by default)");
Check(FirefoxProfiles.CheckOsCerts(Prof("80", null)) == OsCertsState.Ok, "an abandoned Firefox 80 profile is not flagged");
Check(FirefoxProfiles.CheckOsCerts(Prof("147", Off)) == OsCertsState.Disabled, "switched off: Disabled");
Check(FirefoxProfiles.CheckOsCerts(Prof("147", On)) == OsCertsState.Ok, "switched on: fine");
Check(FirefoxProfiles.CheckOsCerts(Prof("74", On)) == OsCertsState.TooOld, "Firefox 74 cannot do it at all");
var list = new List<FirefoxProfile> { Prof("147", Off), Prof("147", null), Prof("60", null) };
var fixedOnes = FirefoxProfiles.EnableOsCerts(list);
Check(fixedOnes.Count == 1 && FirefoxProfiles.CheckOsCerts(list[0]) == OsCertsState.Ok, "EnableOsCerts fixes the profile that was off");
Check(!File.Exists(Path.Combine(list[1].Dir, "user.js")) && !File.Exists(Path.Combine(list[2].Dir, "user.js")), "profiles that were fine are not touched");

Console.WriteLine("finding profiles: Windows and macOS layout (profiles.ini, Profiles/...)");
var root = Temp();
var p1 = Path.Combine(root, "Profiles", "abc12345.default-release"); Profile(p1);
var p2 = Path.Combine(root, "Profiles", "def67890.default"); Profile(p2);
Directory.CreateDirectory(Path.Combine(root, "Profiles", "not-a-profile"));
Write(root, "profiles.ini", "﻿[Install308046B0AF4A39CB]\r\nDefault=Profiles/abc12345.default-release\r\nLocked=1\r\n\r\n[Profile1]\r\nName=default\r\nIsRelative=1\r\nPath=Profiles/def67890.default\r\n\r\n[Profile0]\r\nName=default-release\r\nIsRelative=1\r\nPath=Profiles/abc12345.default-release\r\nDefault=1\r\n\r\n[General]\r\nStartWithLastProfile=1\r\nVersion=2\r\n");
var found = FirefoxProfiles.Find(root);
Check(found.Count == 2 && found.Any(x => x.Dir == p1) && found.Any(x => x.Dir == p2), "two profiles, no duplicates, the folder that is no profile is ignored (profiles.ini has a BOM and CRLF)");
File.Delete(Path.Combine(root, "profiles.ini"));
Check(FirefoxProfiles.Find(root).Count == 2, "without profiles.ini the folder scan finds them");
Check(FirefoxProfiles.Find(Path.Combine(root, "missing")).Count == 0, "a missing folder gives an empty list");
Check(FirefoxProfiles.Find(root, "Snap").All(x => x.Kind == "Snap"), "the kind (Snap / Flatpak) is passed on");

Console.WriteLine("Linux: where the app looks for Firefox");
var home = Temp();
Environment.SetEnvironmentVariable("HOME", home);
Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", null);
Check(BrowserSetup.FindTargets().Count == 0 && BrowserSetup.FindSandboxedBrowsers().Count == 0, "nothing installed: nothing found");
var legacy = Path.Combine(home, ".mozilla", "firefox");
Profile(Path.Combine(legacy, "abcd1234.default-release"), "146");
Write(legacy, "profiles.ini", "[Profile0]\nName=default-release\nIsRelative=1\nPath=abcd1234.default-release\nDefault=1\n");
var xdg = Path.Combine(home, ".config", "mozilla", "firefox");
Profile(Path.Combine(xdg, "wxyz5678.default-release"), "147");
Write(xdg, "profiles.ini", "[Profile0]\nName=default-release\nIsRelative=1\nPath=wxyz5678.default-release\nDefault=1\n");
var custom = Path.Combine(home, "My Docs", "ff profile");
Profile(custom, "147");
File.AppendAllText(Path.Combine(legacy, "profiles.ini"), "\n[Profile1]\nName=custom\nIsRelative=0\nPath=" + custom + "\n");
var targets = BrowserSetup.FindTargets();
Check(targets.Count == 3 && targets.All(t => t.Label == "Firefox"), "three Firefox profiles (got " + targets.Count + ")");
Check(targets.Any(t => t.Dir == Path.Combine(xdg, "wxyz5678.default-release")), "a Firefox 147+ profile under ~/.config/mozilla/firefox is found");
Check(targets.Any(t => t.Dir == custom), "a profile with an absolute path in profiles.ini is found");
Profile(Path.Combine(home, "snap", "firefox", "common", ".mozilla", "firefox", "snap1.default"), "146");
Profile(Path.Combine(home, ".var", "app", "org.mozilla.firefox", ".mozilla", "firefox", "flat1.default"), "146");
Check(BrowserSetup.FindSandboxedBrowsers().SequenceEqual(new[] { "Firefox (Snap)", "Firefox (Flatpak)" }), "Snap and Flatpak Firefox are recognised");
Check(BrowserSetup.FindTargets().Count == 3, "and are not offered as targets: the module cannot be loaded there");
var cfg = Path.Combine(home, "cfg-elsewhere");
Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", cfg);
Profile(Path.Combine(cfg, "mozilla", "firefox", "elsewhere.default"), "147");
Write(Path.Combine(cfg, "mozilla", "firefox"), "profiles.ini", "[Profile0]\r\nName=default\r\nIsRelative=1\r\nPath=elsewhere.default\r\nDefault=1\r\n");
Check(BrowserSetup.FindTargets().Any(t => t.Dir == Path.Combine(cfg, "mozilla", "firefox", "elsewhere.default")), "XDG_CONFIG_HOME is respected");

Console.WriteLine("Linux: Chrome, Chromium, Edge, Brave (one shared NSS database)");
Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", null);
var bin = Temp();
Environment.SetEnvironmentVariable("PATH", bin);                     // only the fake commands made below are "installed"
void Command(string name, string script = "#!/bin/sh\nexit 0\n") { var f = Path.Combine(bin, name); File.WriteAllText(f, script); File.SetUnixFileMode(f, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute); }
string Chromium(bool create = true) => BrowserSetup.FindTargets(create).Where(t => t.Label != "Firefox").Select(t => t.Label).FirstOrDefault();
var legacyDb = Path.Combine(home, ".pki", "nssdb"); var xdgDb = Path.Combine(home, ".local", "share", "pki", "nssdb");

Check(Chromium() == null, "no Chromium-based browser installed: no database to make");
Command("microsoft-edge-stable");
var edge = BrowserSetup.FindTargets(true).Where(t => t.Label != "Firefox").ToList();
Check(edge.Count == 1 && edge[0].Label == "Edge" && edge[0].Dir == legacyDb, "Edge alone (its command is microsoft-edge-stable): a database is planned in ~/.pki/nssdb, labelled Edge");
Check(Chromium(create: false) == null, "nothing is planned unless asked to create the database");
Command("google-chrome-stable");
Check(Chromium() == "Chrome / Edge", "Chrome and Edge share the database: label \"" + Chromium() + "\"");
File.Delete(Path.Combine(bin, "google-chrome-stable")); File.Delete(Path.Combine(bin, "microsoft-edge-stable"));
Command("chromium-browser", "#!/bin/sh\n# stub of the Snap version\nexec /snap/bin/chromium \"$@\"\n");
Check(Chromium() == null, "Ubuntu's chromium-browser stub for the Snap is not an installed Chromium");
Command("chromium", "#!/bin/sh\nexec /usr/lib/chromium/chromium \"$@\"\n");
File.Delete(Path.Combine(bin, "chromium-browser"));
Check(Chromium() == "Chromium", "a regular chromium command counts");
File.Delete(Path.Combine(bin, "chromium"));
Directory.CreateDirectory(Path.Combine(home, ".config", "microsoft-edge"));
Check(Chromium() == "Edge", "Edge is recognised by its config folder even when its command is not on PATH");
Directory.Delete(Path.Combine(home, ".config", "microsoft-edge"));

Directory.CreateDirectory(legacyDb); File.WriteAllText(Path.Combine(legacyDb, "cert9.db"), "");
Directory.CreateDirectory(xdgDb); File.WriteAllText(Path.Combine(xdgDb, "cert9.db"), "");
var dbs = BrowserSetup.FindTargets().Where(t => t.Label != "Firefox").Select(t => t.Dir).ToList();
Check(dbs.SequenceEqual(new[] { legacyDb, xdgDb }), "both shared databases are targets (Chromium 146+ reads the new one unless the old one exists)");
Check(BrowserSetup.FindTargets().First(t => t.Dir == legacyDb).Label == "Chrome / Chromium / Edge", "with no browser found the database gets the general name");
var dataElsewhere = Path.Combine(home, "data-elsewhere", "pki", "nssdb"); Directory.CreateDirectory(dataElsewhere); File.WriteAllText(Path.Combine(dataElsewhere, "cert9.db"), "");
Environment.SetEnvironmentVariable("XDG_DATA_HOME", Path.Combine(home, "data-elsewhere"));
Check(BrowserSetup.FindTargets().Any(t => t.Dir == dataElsewhere), "XDG_DATA_HOME is respected");
Environment.SetEnvironmentVariable("XDG_DATA_HOME", null);

Directory.CreateDirectory(Path.Combine(home, "snap", "chromium"));
Directory.CreateDirectory(Path.Combine(home, ".var", "app", "com.microsoft.Edge"));
Directory.CreateDirectory(Path.Combine(home, ".var", "app", "com.google.Chrome"));
Check(BrowserSetup.FindSandboxedBrowsers().SequenceEqual(new[] { "Firefox (Snap)", "Firefox (Flatpak)", "Chrome (Flatpak)", "Chromium (Snap)", "Edge (Flatpak)" }),
      "Snap and Flatpak browsers are named: " + string.Join(", ", BrowserSetup.FindSandboxedBrowsers()));

Console.WriteLine("Linux: why NSS refused the module");
Check(BrowserSetup.WhyFailed("ERROR: Failed to add module \"Srb Id PKCS11\". Probable cause : \"A PKCS #11 module returned CKR_FUNCTION_FAILED, indicating that the requested function could not be performed.\".") == "noservice", "CKR_FUNCTION_FAILED: the smart card service is not running");
Check(BrowserSetup.WhyFailed("Probable cause : \"/opt/supercelik/pkcs11/libsrb-id-pkcs11.so: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.36' not found (required by /opt/supercelik/pkcs11/libsrb-id-pkcs11.so)\".") == "oldlibc", "version GLIBC_2.36 not found: the C library is too old");
Check(BrowserSetup.WhyFailed("Probable cause : \"libpcsclite.so.1: cannot open shared object file: No such file or directory\".") == "nolib", "libpcsclite.so.1 missing");
Check(BrowserSetup.WhyFailed("SEC_ERROR_BAD_DATABASE: security library: bad database.") == null, "anything else: no special reason");

Console.WriteLine("Linux: what `modutil -list` says about the module (real NSS 3.98 output, with a stand-in module that behaves like srb-id-pkcs11)");
string Listing(string module) =>
    "Listing of PKCS #11 Modules\n-----------------------------------------------------------\n" +
    "  1. NSS Internal PKCS #11 Module\n\t   slots: 2 slots attached\n\t  status: loaded\n\n\t   slot: NSS Internal Cryptographic Services\n\t  token: NSS Generic Crypto Services\n" +
    "\t    uri: pkcs11:token=NSS%20Generic%20Crypto%20Services;manufacturer=Mozilla%20Foundation;serial=0000000000000000;model=NSS%203\n\n" +
    "\t   slot: NSS User Private Key and Certificate Services\n\t  token: NSS Certificate DB\n\t    uri: pkcs11:token=NSS%20Certificate%20DB;manufacturer=Mozilla%20Foundation;serial=0000000000000000;model=NSS%203\n" +
    module + "-----------------------------------------------------------\n";
const string Head = "  2. Srb Id PKCS11\n\tlibrary name: /opt/supercelik/pkcs11/libsrb-id-pkcs11.so\n\t   uri: pkcs11:library-description=srb-id;library-version=0.6\n";
var withCard = BrowserSetup.ParseListing(Listing(Head + "\t slots: 1 slot attached\n\tstatus: loaded\n\n\t slot: ACS ACR39U 00 00\n\ttoken: Serbian eID card\n\t  uri: pkcs11:token=Serbian%20eID%20card;serial=0001\n"));
Check(withCard == new BrowserSetup.ModuleState(true, true, 1, "Serbian eID card"), "reader and card: registered, loaded, 1 slot, the card's name");
var noCard = BrowserSetup.ParseListing(Listing(Head + "\t slots: 1 slot attached\n\tstatus: loaded\n\n\t slot: ACS ACR39U 00 00\n\ttoken: \n\t  uri: pkcs11:\n"));
Check(noCard == new BrowserSetup.ModuleState(true, true, 1, ""), "reader without a card: 1 slot, empty token");
var noReader = BrowserSetup.ParseListing(Listing(Head + "\t slots: There are no slots attached to this module\n\tstatus: loaded\n"));
Check(noReader == new BrowserSetup.ModuleState(true, true, 0, ""), "no reader: no slots");
var stopped = BrowserSetup.ParseListing(Listing("  2. Srb Id PKCS11\n\tlibrary name: /opt/supercelik/pkcs11/libsrb-id-pkcs11.so\n\t slots: There are no slots attached to this module\n\tstatus: Not loaded\n"));
Check(stopped == new BrowserSetup.ModuleState(true, false, 0, ""), "the module does not start (service stopped, library missing): registered, not loaded");
var absent = BrowserSetup.ParseListing(Listing(""));
Check(absent == new BrowserSetup.ModuleState(false, false, 0, ""), "a database without the module: not registered (the other modules' slots and tokens are not counted)");
var other = BrowserSetup.ParseListing(Listing("  2. OpenSC smartcard framework\n\tlibrary name: opensc-pkcs11.so\n\t slots: 1 slot attached\n\tstatus: loaded\n\n\t slot: Reader\n\ttoken: Someone's card\n"));
Check(!other.Registered && other.Token == "", "another card module is not taken for ours");
var third = BrowserSetup.ParseListing(Listing("  2. OpenSC smartcard framework\n\t slots: 1 slot attached\n\tstatus: loaded\n\n\t slot: Reader\n\ttoken: Someone's card\n" +
    "  3. Srb Id PKCS11\n\tlibrary name: /x.so\n\t slots: 1 slot attached\n\tstatus: loaded\n\n\t slot: R\n\ttoken: Mine\n"));
Check(third == new BrowserSetup.ModuleState(true, true, 1, "Mine"), "our module listed after another one: only its own slots and token count");
Check(BrowserSetup.ParseListing("") == new BrowserSetup.ModuleState(false, false, 0, ""), "empty output: not registered");

Console.WriteLine("Linux: what to do next");
var none = new List<string>();
BrowserSetup.Diagnosis Dg(string kind = "checked", string[] connected = null, string[] missing = null, bool loaded = true, string why = null, int slots = 1, string token = "Card", string[] sandboxed = null) =>
    new(kind, (connected ?? new[] { "Firefox" }).ToList(), (missing ?? Array.Empty<string>()).ToList(), (sandboxed ?? Array.Empty<string>()).ToList(), loaded, why, slots, token);
Check(BrowserSetup.NextStep(Dg("nomodule"), 1, true) == "nomodule" && BrowserSetup.NextStep(Dg("notool"), 1, true) == "notool"
      && BrowserSetup.NextStep(Dg("none"), 1, true) == "none" && BrowserSetup.NextStep(Dg("sandboxed"), 1, true) == "sandboxed"
      && BrowserSetup.NextStep(Dg("stuck"), 1, true) == "stuck", "nothing to check: the kind itself (no module / no tool / no browser / only sandboxed ones / the service does not answer)");
Check(BrowserSetup.NextStep(Dg(missing: new[] { "Chrome" }), 1, true) == "connect", "a browser without the module: connect it first");
Check(BrowserSetup.NextStep(Dg(loaded: false, why: "noservice"), 1, true) == "noservice", "does not start, service stopped");
Check(BrowserSetup.NextStep(Dg(loaded: false, why: "oldlibc"), 1, true) == "oldlibc" && BrowserSetup.NextStep(Dg(loaded: false, why: "nolib"), 1, true) == "nolib", "does not start: old C library / missing libpcsclite");
Check(BrowserSetup.NextStep(Dg(loaded: false), 1, true) == "noload", "does not start, reason unknown");
Check(BrowserSetup.NextStep(Dg(), 1, true) == "ok", "the module sees the card: all in order");
Check(BrowserSetup.NextStep(Dg(sandboxed: new[] { "Firefox (Snap)" }), 1, true) == "sandboxed", "all in order, but a Snap browser stands next to the others: not \"all good\", the sandbox is what is left to say");
Check(BrowserSetup.NextStep(Dg(sandboxed: new[] { "Firefox (Snap)" }, missing: new[] { "Chrome" }), 1, true) == "connect"
      && BrowserSetup.NextStep(Dg(sandboxed: new[] { "Firefox (Snap)" }, token: "", slots: 1), 1, false) == "nocard", "a real problem still comes first, the sandboxed browser does not hide it");
Check(BrowserSetup.NextStep(Dg(slots: 0, token: ""), 0, false) == "noreader", "no reader anywhere: plug it in");
Check(BrowserSetup.NextStep(Dg(slots: 0, token: ""), 1, true) == "reinsert", "the app sees a reader, the module sees none: take the card out and in");
Check(BrowserSetup.NextStep(Dg(token: ""), 1, false) == "nocard", "reader without a card: insert it");
Check(BrowserSetup.NextStep(Dg(token: ""), 1, true) == "reinsert", "the app sees the card, the module does not: take it out and in, restart the service");

Console.WriteLine(failures == 0 ? "ALL OK" : failures + " FAILED");
return failures;
