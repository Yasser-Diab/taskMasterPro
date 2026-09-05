#ifndef MyAppVersion
  #define MyAppVersion "0.0.30"
#endif
#ifndef MyAppDisplayVersion
  #define MyAppDisplayVersion MyAppVersion
#endif
#ifndef SourceDir
  #error SourceDir must point to the Flutter Windows release folder
#endif
#ifndef OutputDir
  #error OutputDir must point to the release output folder
#endif

#define MyAppName "DayVector"
#define MyAppPublisher "Y. A. Diab"
#define MyAppExeName "dayvector.exe"

[Setup]
AppId={{7A13549B-2DF3-4D0B-9C04-605F8D150025}
AppName={#MyAppName}
AppVersion={#MyAppDisplayVersion}
AppVerName={#MyAppName} {#MyAppDisplayVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://dayvector.com
AppSupportURL=mailto:yasserdiabhassan@gmail.com
AppUpdatesURL=https://github.com/Yasser-Diab/taskMasterPro/releases
DefaultDirName={localappdata}\Programs\DayVector
DefaultGroupName=DayVector
; Keep the stable AppId for in-place upgrades, but do not let Inno reuse the
; pre-DayVector install folder stored by an older release.
UsePreviousAppDir=no
UsePreviousGroup=no
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=DayVector-{#MyAppVersion}-Windows-Setup
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
VersionInfoDescription=DayVector installer
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\taskmaster_pro.exe"
Type: files; Name: "{autoprograms}\TaskMaster Pro.lnk"
Type: files; Name: "{autodesktop}\TaskMaster Pro.lnk"
Type: files; Name: "{userstartup}\TaskMaster Pro.lnk"

[Icons]
Name: "{autoprograms}\DayVector"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\DayVector"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\DayVector"; Filename: "{app}\{#MyAppExeName}"; Tasks: startup

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts"; Flags: unchecked
Name: "startup"; Description: "Start DayVector with Windows"; GroupDescription: "Background operation"; Flags: unchecked

[Registry]
Root: HKCU; Subkey: "Software\Classes\pro.taskmaster.app"; ValueType: string; ValueName: ""; ValueData: "URL:DayVector authentication"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\pro.taskmaster.app"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\pro.taskmaster.app\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCU; Subkey: "Software\Classes\pro.taskmaster.app\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch DayVector"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  LegacyDir: String;
  CurrentDir: String;
  LegacyUninstaller: String;
  LegacyDayVectorExe: String;
  LegacyTaskMasterExe: String;
begin
  if CurStep <> ssPostInstall then
    Exit;

  LegacyDir := ExpandConstant('{localappdata}\Programs\TaskMaster Pro');
  CurrentDir := ExpandConstant('{app}');
  if CompareText(AddBackslash(LegacyDir), AddBackslash(CurrentDir)) = 0 then
    Exit;

  LegacyUninstaller := AddBackslash(LegacyDir) + 'unins000.exe';
  LegacyDayVectorExe := AddBackslash(LegacyDir) + '{#MyAppExeName}';
  LegacyTaskMasterExe := AddBackslash(LegacyDir) + 'taskmaster_pro.exe';

  { Only retire the exact former product directory when it still has the
    Inno uninstaller and one of the known application executables. }
  if DirExists(LegacyDir) and FileExists(LegacyUninstaller) and
     (FileExists(LegacyDayVectorExe) or FileExists(LegacyTaskMasterExe)) then
  begin
    Log('Retiring the verified legacy TaskMaster Pro install directory.');
    if not DelTree(LegacyDir, True, True, True) then
      Log('The verified legacy install directory could not be removed completely.');
  end;
end;
