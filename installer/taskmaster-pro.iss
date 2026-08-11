#ifndef MyAppVersion
  #define MyAppVersion "0.0.28"
#endif
#ifndef SourceDir
  #error SourceDir must point to the Flutter Windows release folder
#endif
#ifndef OutputDir
  #error OutputDir must point to the release output folder
#endif

#define MyAppName "TaskMaster Pro"
#define MyAppPublisher "Y. A. Diab"
#define MyAppExeName "taskmaster_pro.exe"

[Setup]
AppId={{7A13549B-2DF3-4D0B-9C04-605F8D150025}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/Yasser-Diab/taskMasterPro
AppSupportURL=mailto:yasserdiabhassan@gmail.com
AppUpdatesURL=https://github.com/Yasser-Diab/taskMasterPro/releases
DefaultDirName={localappdata}\Programs\TaskMaster Pro
DefaultGroupName=TaskMaster Pro
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=TaskMasterPro-{#MyAppVersion}-Windows-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=yes
ChangesAssociations=yes
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=TaskMaster Pro installer
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\TaskMaster Pro"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\TaskMaster Pro"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\TaskMaster Pro"; Filename: "{app}\{#MyAppExeName}"; Tasks: startup

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts"; Flags: unchecked
Name: "startup"; Description: "Start TaskMaster Pro with Windows"; GroupDescription: "Background operation"; Flags: unchecked

[Registry]
Root: HKCU; Subkey: "Software\Classes\pro.taskmaster.app"; ValueType: string; ValueName: ""; ValueData: "URL:TaskMaster Pro authentication"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\pro.taskmaster.app"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\pro.taskmaster.app\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCU; Subkey: "Software\Classes\pro.taskmaster.app\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch TaskMaster Pro"; Flags: nowait postinstall skipifsilent
