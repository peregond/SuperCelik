; Inno Setup script for the 32-bit installer for Windows XP / Vista / 7 (built in CI with Inno Setup 5.6.1, the last
; version whose installers run on Windows XP: iscc /DAppVersion=x.y.z windows\installer-legacy.iss)
#ifndef AppVersion
  #define AppVersion "0.9.9"
#endif

[Setup]
AppId={{2E6F3A5C-8B41-4D7E-A1D4-3F9C7B52E0A8}
AppName=Super Čelik
AppVersion={#AppVersion}
AppPublisher=peregond
; a 32-bit program also on 64-bit Windows 7 (the 64-bit Windows keeps its own, 64-bit card driver next to the 32-bit one)
DefaultDirName={pf32}\Super Čelik
DefaultGroupName=Super Čelik
OutputDir=..\dist
OutputBaseFilename=SuperCelik-{#AppVersion}-windows-x86-legacy-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
MinVersion=0,5.1sp3
PrivilegesRequired=admin
UninstallDisplayIcon={app}\SuperCelik.exe
SetupIconFile=SerbiaID.Windows\app.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "serbian"; MessagesFile: "Serbian.isl"

[CustomMessages]
english.InstallingDotNet=Installing Microsoft .NET Framework 4.0 (this can take a few minutes)...
russian.InstallingDotNet=Установка Microsoft .NET Framework 4.0 (это может занять несколько минут)...
serbian.InstallingDotNet=Instalacija Microsoft .NET Framework 4.0 (može potrajati nekoliko minuta)...
english.DotNetFailed=Microsoft .NET Framework 4.0 could not be installed (error %1). Super Čelik needs it: install it from Microsoft and run this setup again.
russian.DotNetFailed=Не удалось установить Microsoft .NET Framework 4.0 (ошибка %1). Он нужен для Super Čelik: установите его с сайта Microsoft и запустите установку ещё раз.
serbian.DotNetFailed=Microsoft .NET Framework 4.0 nije mogao da se instalira (greška %1). Potreban je za Super Čelik: instalirajte ga sa Microsoft sajta i ponovo pokrenite instalaciju.

[Files]
; Microsoft .NET Framework 4.0 (Full) redistributable: installed first when the computer does not have .NET 4 yet
; (downloaded by CI, see build.yml)
Source: "..\dist\dotnetfx40_Full_x86_x64.exe"; DestDir: "{tmp}"; Flags: dontcopy
; framework-dependent publish output (see build.yml), both card minidrivers (x86 and x64) are in it
Source: "..\dist\win-x86-legacy\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

; The smart card minidriver for browser login (Chrome / Edge / Firefox ESR with the system store) goes next to the
; system DLLs, where Windows looks for it. Card minidrivers need Windows Vista or newer: nothing is copied on XP.
Source: "..\dist\win-x86-legacy\SuperCelikMD.dll"; DestDir: "{sys}"; MinVersion: 0,6.0; Check: not Is64BitInstallMode; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "..\dist\win-x86-legacy\SuperCelikMD.dll"; DestDir: "{syswow64}"; MinVersion: 0,6.0; Check: Is64BitInstallMode; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "..\dist\win-x86-legacy\SuperCelikMD64.dll"; DestName: "SuperCelikMD.dll"; DestDir: "{sys}"; MinVersion: 0,6.0; Check: Is64BitInstallMode; Flags: ignoreversion restartreplace uninsrestartdelete 64bit

[Icons]
Name: "{group}\Super Čelik"; Filename: "{app}\SuperCelik.exe"
Name: "{commondesktop}\Super Čelik"; Filename: "{app}\SuperCelik.exe"; Tasks: desktopicon

; remember the installer language: the app uses it on first launch
[Registry]
Root: HKCU; Subkey: "Software\SuperCelik"; ValueType: string; ValueName: "Lang"; ValueData: "{language}"; Flags: uninsdeletekey


[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"

[Run]
; register the card driver for the exact ATR of the Gemalto-based Serbian eID (the app writes both registry views of
; a 64-bit Windows; Windows Vista or newer only)
Filename: "{app}\SuperCelik.exe"; Parameters: "--register-driver 3BFF9400008131804380318065B0850201F3120FFF82900079"; MinVersion: 0,6.0; Check: DotNetReady; Flags: runhidden waituntilterminated
; register the driver for the cards that are in a reader right now (the installer is elevated); never fails the install
Filename: "{app}\SuperCelik.exe"; Parameters: "--register-driver auto"; Check: DotNetReady; Flags: runhidden waituntilterminated
; interactive install: "Launch Super Čelik" checkbox on the last page
Filename: "{app}\SuperCelik.exe"; Description: "{cm:LaunchProgram,Super Čelik}"; Check: DotNetReady; Flags: nowait postinstall skipifsilent runasoriginaluser
; silent install (auto-update from inside the app): start the new version again automatically
Filename: "{app}\SuperCelik.exe"; Flags: nowait runasoriginaluser; Check: SilentAndDotNetReady

[UninstallRun]
; take the browser-login driver out of Windows (asks for administrator rights); nothing happens if it was never installed
Filename: "{app}\SuperCelik.exe"; Parameters: "--unregister-driver"; RunOnceId: "UnregisterDriver"; Flags: runhidden waituntilterminated

[Code]
var
  RestartNeeded: Boolean;

// .NET Framework 4.0 or newer (Client or Full profile) is what the program runs on
function HasDotNet4(): Boolean;
var
  Install: Cardinal;
begin
  Result := (RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Install', Install) and (Install = 1)) or
            (RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Client', 'Install', Install) and (Install = 1));
end;

// the program can be started now: .NET is there and no restart is waiting for it
function DotNetReady(): Boolean;
begin
  Result := (not RestartNeeded) and HasDotNet4();
end;

function SilentAndDotNetReady(): Boolean;
begin
  Result := WizardSilent and DotNetReady();
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
  Switches: String;
begin
  if (CurStep = ssInstall) and (not HasDotNet4()) then
  begin
    ExtractTemporaryFile('dotnetfx40_Full_x86_x64.exe');
    WizardForm.StatusLabel.Caption := CustomMessage('InstallingDotNet');
    if WizardSilent then Switches := '/q /norestart' else Switches := '/passive /norestart';
    if Exec(ExpandConstant('{tmp}\dotnetfx40_Full_x86_x64.exe'), Switches, '', SW_SHOW, ewWaitUntilTerminated, Code) then
    begin
      if Code = 3010 then RestartNeeded := True           // installed, Windows wants a restart
      else if (Code <> 0) and (Code <> 1638) and not HasDotNet4() then
        if not WizardSilent then MsgBox(FmtMessage(CustomMessage('DotNetFailed'), [IntToStr(Code)]), mbError, MB_OK);
    end
    else if not WizardSilent then
      MsgBox(FmtMessage(CustomMessage('DotNetFailed'), [SysErrorMessage(Code)]), mbError, MB_OK);
  end;
end;

function NeedRestart(): Boolean;
begin
  Result := RestartNeeded;
end;
