; Inno Setup script for the Windows installer (built in CI: iscc /DAppVersion=x.y.z windows\installer.iss)
#ifndef AppVersion
  #define AppVersion "0.9.7"
#endif

[Setup]
AppId={{6B1B3D0E-5A52-4B7A-9C0B-5C0E1A5E7C11}
AppName=Super Celik
AppVersion={#AppVersion}
AppPublisher=peregond
DefaultDirName={autopf}\Super Celik
DefaultGroupName=Super Celik
OutputDir=..\dist
OutputBaseFilename=SuperCelik-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
UninstallDisplayIcon={app}\SuperCelik.exe
SetupIconFile=SerbiaID.Windows\app.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "serbian"; MessagesFile: "Serbian.isl"

[Files]
; self-contained publish output (see build.yml): dotnet publish -c Release -r win-x64 --self-contained
Source: "..\dist\win-x64\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

; the smart card minidriver for browser login (Chrome / Edge) goes next to the system DLLs, where Windows looks for it
Source: "..\dist\win-x64\SuperCelikMD.dll"; DestDir: "{sys}"; Flags: ignoreversion restartreplace uninsrestartdelete

[Icons]
Name: "{group}\Super Celik"; Filename: "{app}\SuperCelik.exe"
Name: "{autodesktop}\Super Celik"; Filename: "{app}\SuperCelik.exe"; Tasks: desktopicon

; remember the installer language: the app uses it on first launch
[Registry]
Root: HKCU; Subkey: "Software\SuperCelik"; ValueType: string; ValueName: "Lang"; ValueData: "{language}"; Flags: uninsdeletekey

; Smart card driver registration (Windows matches a card to its minidriver by ATR). The exact ATR of the
; Gemalto-based Serbian eID is registered here (exact, not a family mask: a mask would also catch other Gemalto
; cards and take them away from their own drivers); other ATRs are registered by `SuperCelik.exe --register-driver auto` right after
; the install (cards in a reader now) and by the app itself the first time such a card is inserted. The driver
; checks the CardEdge applet itself, so a card of the same family with another applet is declined.
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Cryptography\Calais\SmartCards\SuperCelik-Gemalto-eID"; ValueType: binary; ValueName: "ATR"; ValueData: "3B FF 94 00 00 81 31 80 43 80 31 80 65 B0 85 02 01 F3 12 0F FF 82 90 00 79"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Cryptography\Calais\SmartCards\SuperCelik-Gemalto-eID"; ValueType: binary; ValueName: "ATRMask"; ValueData: "FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF"
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Cryptography\Calais\SmartCards\SuperCelik-Gemalto-eID"; ValueType: string; ValueName: "Crypto Provider"; ValueData: "Microsoft Base Smart Card Crypto Provider"
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Cryptography\Calais\SmartCards\SuperCelik-Gemalto-eID"; ValueType: string; ValueName: "Smart Card Key Storage Provider"; ValueData: "Microsoft Smart Card Key Storage Provider"
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Cryptography\Calais\SmartCards\SuperCelik-Gemalto-eID"; ValueType: string; ValueName: "80000001"; ValueData: "SuperCelikMD.dll"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"

[Run]
; register the driver for the cards that are in a reader right now (the installer is elevated); never fails the install
Filename: "{app}\SuperCelik.exe"; Parameters: "--register-driver auto"; Flags: runhidden waituntilterminated
; interactive install: "Launch Super Celik" checkbox on the last page
Filename: "{app}\SuperCelik.exe"; Description: "{cm:LaunchProgram,Super Celik}"; Flags: nowait postinstall skipifsilent runasoriginaluser
; silent install (auto-update from inside the app): start the new version again automatically
Filename: "{app}\SuperCelik.exe"; Flags: nowait runasoriginaluser; Check: WizardSilent

[UninstallRun]
; take the browser-login driver out of Windows (asks for administrator rights); nothing happens if it was never installed
Filename: "{app}\SuperCelik.exe"; Parameters: "--unregister-driver"; RunOnceId: "UnregisterDriver"; Flags: runhidden waituntilterminated
