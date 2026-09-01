; Inno Setup script for the Ion Strikers Windows client.
;
; Built from CI with defines:
;   MyAppVersion     full tag version (e.g. 0.0.2-rc1)
;   MyAppVersionCore numeric core for VersionInfo (e.g. 0.0.2)
;   SourceDir        directory holding the Godot Windows export
;   OutputDir        where the setup .exe is written
;   OutputName       base filename without .exe
;
; Godot does not emit installers; the docs point at Inno Setup / NSIS.
; We use Inno Setup only.

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MyAppVersionCore
  #define MyAppVersionCore "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "stage"
#endif
#ifndef OutputDir
  #define OutputDir "dist"
#endif
#ifndef OutputName
  #define OutputName "ion-strikers-setup"
#endif

#define MyAppName "Ion Strikers"
#define MyAppPublisher "Ion Strikers"
#define MyAppExeName "ion-strikers.exe"

[Setup]
; Stable across releases so upgrades replace the previous install.
AppId={{A7C3E91B-4F2D-4B8A-9E15-1D6C8A0B3F47}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion={#MyAppVersionCore}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
