#define AppName "LinkUp"
#define AppExecutable "linkup.exe"

[Setup]
AppId=LinkUp.mel0nyrame
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=LinkUp
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\..\build\windows\installer
OutputBaseFilename=LinkUp-Setup-{#AppVersion}
UninstallDisplayIcon={app}\{#AppExecutable}
Uninstallable=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExecutable}"

[UninstallRun]
Filename: "{sys}\reg.exe"; Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v ""LinkUp"" /f /reg:64"; Flags: runhidden; RunOnceId: "RemoveLinkUpAutoStart"
