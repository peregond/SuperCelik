; Inno Setup script for the Windows installer (built in CI: iscc /DAppVersion=x.y.z windows\installer.iss)
#ifndef AppVersion
  #define AppVersion "0.1.0"
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
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
UninstallDisplayIcon={app}\SuperCelik.exe
SetupIconFile=SerbiaID.Windows\app.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Files]
; self-contained publish output (see build.yml): dotnet publish -c Release -r win-x64 --self-contained
Source: "..\dist\win-x64\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Super Celik"; Filename: "{app}\SuperCelik.exe"
Name: "{autodesktop}\Super Celik"; Filename: "{app}\SuperCelik.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"

[Run]
Filename: "{app}\SuperCelik.exe"; Description: "{cm:LaunchProgram,Super Celik}"; Flags: nowait postinstall skipifsilent
